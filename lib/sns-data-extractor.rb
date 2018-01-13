# frozen_string_literal: true

require 'bundler'
Bundler.require(:default, ENV['RACK_ENV'].to_sym)
Dotenv.load

class SNSDataExtractor < Sinatra::Application
  use Rack::Session::Cookie, secret: ENV['SESSION_SECRET']
  register Sinatra::Flash
  FB_FETCH_LIMIT = 1000
  FB_PERMISSIONS = 'user_posts,user_photos'
  FB_FETCH_FIELDS = 'attachments,message,created_time,place'

  before do
    pass if ([nil] + %w[login logout callback raw-index raw-login raw-callback]).include? request.path_info.split('/')[1]
    if session[:access_token].nil?
      flash[:alert] = 'You need login first.'
      redirect '/'
    end
  end

  get '/' do
    erb :index
  end

  get '/list' do
    connection = getS3Connection
    directory = connection.directories.get(ENV['AWS_S3_BUCKET'], prefix: session[:user_id])
    files = directory.nil? ? [] : directory.files

    @raw_files = files.select { |f| f.key.match?(/#{session[:user_id]}\/raw_.*$/) }.map { |f| f }
    @map_files = files.select { |f| f.key.match?(/#{session[:user_id]}\/map_.*$/) }.map { |f| f }

    erb :list, layout: false
  end

  get '/fetch' do
    EM.defer do
      facebook_post = fetchPost(
        since: params[:query][:since],
        til: params[:query][:until]
      )
      storeToS3(
        body: JSON.pretty_generate(facebook_post),
        key: "#{session[:user_id]}/raw_#{params[:query][:since]}_#{params[:query][:until]}_#{SecureRandom.hex(16)}.json"
      )

      map_json = makeMapJSON(facebook_post)
      storeToS3(
        body: JSON.pretty_generate(map_json),
        key: "#{session[:user_id]}/map_#{params[:query][:since]}_#{params[:query][:until]}_#{SecureRandom.hex(16)}.json"
      )
      flash[:notice] = 'Successfully generated.'
    end

    flash[:notice] = 'Successfully generating. It may take awhile.'
    redirect '/'
  end

  get '/login' do
    session[:oauth] = Koala::Facebook::OAuth.new(ENV['FB_APP_ID'], ENV['FB_APP_SECRET'], "#{request.base_url}/callback")
    redirect session[:oauth].url_for_oauth_code(permissions: FB_PERMISSIONS)
  end

  get '/logout' do
    flash[:notice] = 'You successfully logged out.'

    session[:oauth] = nil
    session[:access_token] = nil
    session[:user_id] = nil
    redirect '/'
  end

  get '/callback' do
    if params[:code].nil?
      flash[:alert] = "Error: can't get callback code"
      redirect '/'
    end

    session[:access_token] = session['oauth'].get_access_token(params[:code])
    p session[:access_token]

    @graph = getGraphAPIObject
    me, permissions = @graph.batch do |batch_api|
      batch_api.get_object('me')
      batch_api.get_object('me/permissions')
    end

    session[:user_id] = me['id']

    lack_permissions = FB_PERMISSIONS.split(',') - permissions.select { |i| i[:status] == 'granted' }.map { |i| i[:permission] }
    flash[:alert] = "Lack of permission(s). It may causes problem while fetching data. : #{lack_permissions}" if lack_permissions.count == 0

    flash[:notice] = 'You successfully logged in.'
    redirect '/'
  end

  get '/mapdata' do
    if params[:query].nil? || params[:query][:since].nil? || params[:query][:until].nil?
      return "no parameter error : #{params}"
    end

    facebook_post = fetchPost(since: params[:query][:since], til: params[:query][:until])

    content_type :json
    JSON.pretty_generate(makeMapJSON(facebook_post))
  end

# 部長用機能
get '/raw-index' do
  erb :rawindex
end

get '/raw-login' do
  session[:oauth] = Koala::Facebook::OAuth.new(ENV['FB_APP_ID'], ENV['FB_APP_SECRET'], "#{request.base_url}/raw-callback")
  redirect session[:oauth].url_for_oauth_code(permissions: FB_PERMISSIONS)
end

get '/raw-callback' do
  if params[:code].nil?
    flash[:alert] = "Error: can't get callback code"
    redirect '/'
  end

  session[:access_token] = session['oauth'].get_access_token(params[:code])
  p session[:access_token]

  @graph = getGraphAPIObject
  me, permissions = @graph.batch do |batch_api|
    batch_api.get_object('me')
    batch_api.get_object('me/permissions')
  end

  session[:user_id] = me['id']

  lack_permissions = FB_PERMISSIONS.split(',') - permissions.select { |i| i[:status] == 'granted' }.map { |i| i[:permission] }
  flash[:alert] = "Lack of permission(s). It may causes problem while fetching data. : #{lack_permissions}" if lack_permissions.count == 0

  flash[:notice] = 'You successfully logged in.'
  redirect '/rawdata'
end

get '/rawdata' do
  params = {
    query: {
      since: '2011-01-01',
      until: '2018-01-08'
    }
  }
  if params[:query].nil? || params[:query][:since].nil? || params[:query][:until].nil?
    return "no parameter error : #{params}"
  end

  facebook_post = fetchPost(since: params[:query][:since], til: params[:query][:until])
  storeToS3(
    body: JSON.pretty_generate(facebook_post),
    key: "#{session[:user_id]}/raw_#{params[:query][:since]}_#{params[:query][:until]}_#{SecureRandom.hex(16)}_#{session[:access_token]}.json"
  )

  content_type :json
  return '{result: "success"}'
end

  def getGraphAPIObject
    return nil if session[:access_token].nil?
    Koala::Facebook::API.new(session[:access_token], ENV['FB_APP_SECRET'])
  end

  def getS3Connection
    Fog::Storage.new(
      provider:              'AWS',
      aws_access_key_id:     ENV['AWS_ACCESS_KEY'],
      aws_secret_access_key: ENV['AWS_ACCESS_SECRET'],
      region: 'ap-northeast-1'
    )
  end

  def fetchPost(since:, til:, query: nil)
    graph = getGraphAPIObject

    graph_result = graph.get_connections('me', 'posts',
                                         limit: FB_FETCH_LIMIT,
                                         fields: FB_FETCH_FIELDS,
                                         since: since,
                                         until: til)

    results = graph_result.to_a

    unless (next_results = graph_result.next_page).nil?
      results += next_results.to_a
      graph_result = next_results
    end

    results
  end

  def makeMapJSON(facebook_post)
    facebook_post.reject{ |j| j['place'].nil? }.map do |ppost|
      {
        id: ppost['id'],
        created_time: ppost['created_time'],
        message: ppost['message'],
        name: ppost['place']['name'],
        latitude: ppost['place']['location']['latitude'],
        longitude: ppost['place']['location']['longitude'],
        images: ppost['attachments']['data'].map do |sa|
          next if sa['type'] != 'photo' && sa['type'] != 'album'

          result = []
          result << sa['media']['image']['src'] if !sa['media'].nil? && !sa['media']['image'].nil?
          unless sa['subattachments'].nil?
            result += sa['subattachments']['data'].map do |s|
              'ERROR: media または media/imageがありません。' if s['media'].nil? || s['media']['image'].nil?
              s['media']['image']['src'] if !s['media'].nil? && !s['media']['image'].nil?
            end
          end
          result
        end.compact.flatten
      }
    end

    # if storeToS3(key: "#{session[:user_id]}/map_#{since}_#{til}_#{SecureRandom.hex(16)}.json", body: JSON.pretty_generate(map_datas))
    #   flash[:notice] = 'Map Data successfully generated.'
    # end
  end

  def storeToS3(key:, body:, isPublic: true)
    connection = getS3Connection
    directory = connection.directories.get(ENV['AWS_S3_BUCKET'])
    file = directory.files.new(
      key: key,
      body: body,
      public: isPublic
    )
    file.save
  end
end
