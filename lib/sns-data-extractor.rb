require 'bundler'
Bundler.require(:default, ENV['RACK_ENV'].to_sym)
Dotenv.load

class SNSDataExtractor < Sinatra::Application
  use Rack::Session::Cookie, secret: ENV['SESSION_SECRET']
  register Sinatra::Flash
  FB_FETCH_LIMIT = 1000
  FB_PERMISSIONS = "user_posts,user_photos"
  FB_FETCH_FIELDS = "attachments,message,created_time,place"

  connection = Fog::Storage.new({
    provider:              'AWS',
    aws_access_key_id:     ENV['AWS_ACCESS_KEY'],
    aws_secret_access_key: ENV['AWS_ACCESS_SECRET'],
    region: "ap-northeast-1"
  })

  before do
     pass if ([nil]+%w[login logout callback]).include? request.path_info.split('/')[1]
     if session[:access_token].nil?
       flash[:alert] = "You need login first."
       redirect '/'
     end
   end

  get '/' do
    erb :index
  end

  get '/list' do
    directory = connection.directories.get(ENV['AWS_S3_BUCKET'], prefix: session[:user_id])
    @files = directory.nil? ? [] : directory.files

    erb :list, layout: false
  end

  get '/fetch' do
    if !params[:query].nil? || !params[:page].nil?
      @graph = getGraphAPIObject

      @graph_result = params[:page] ? @graph.get_page(JSON.parse(params[:page])) :
                                 @graph.get_connections("me", "posts",
                                    params[:query].merge({limit: FB_FETCH_LIMIT, fields: FB_FETCH_FIELDS})
                                  )
      @results = @graph_result.to_a
    end

    while !(next_results = @graph_result.next_page).nil? do
      @results += next_results.to_a
      @graph_result = next_results
    end
    # NGだったら再試行を3回ぐらいやって、駄目なら取れたところまでで返す。

    pretty_json = JSON.pretty_generate(@results)

    directory = connection.directories.get(ENV['AWS_S3_BUCKET'])

    file = directory.files.new({
      :key    => "#{session[:user_id]}/#{params[:query][:since]}_#{params[:query][:until]}_#{SecureRandom.hex(16)}.json",
      :body   => pretty_json,
      :public => true
    })
    file.save

    flash[:notice] = "Successfully generated."
    redirect '/'
  end

  get '/login' do
    session[:oauth] = Koala::Facebook::OAuth.new(ENV['FB_APP_ID'], ENV['FB_APP_SECRET'], "#{request.base_url}/callback")
    redirect session[:oauth].url_for_oauth_code(permissions: FB_PERMISSIONS)
  end

  get '/logout' do
    flash[:notice] = "You successfully logged out."

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

    @graph = getGraphAPIObject
    me, permissions = @graph.batch do |batch_api|
      batch_api.get_object('me')
      batch_api.get_object('me/permissions')
    end

    session[:user_id] = me["id"]

    lack_permissions = FB_PERMISSIONS.split(",") - permissions.select{|i| i[:status] == "granted"}.map{|i| i[:permission]}
    flash[:alert] = "Lack of permission(s). It may causes problem while fetching data. : #{lack_permissions}" if lack_permissions.count == 0

    flash[:notice] = "You successfully logged in."
    redirect '/'
  end

  def getGraphAPIObject
    return nil if session[:access_token].nil?
    Koala::Facebook::API.new(session[:access_token], ENV['FB_APP_SECRET'])
  end

end
