require 'bundler'
Bundler.require(:default, ENV['RACK_ENV'].to_sym)
Dotenv.load

class SNSDataExtractor < Sinatra::Application
  use Rack::Session::Cookie, secret: ENV['SESSION_SECRET']

  get '/' do
    @oauth = Koala::Facebook::OAuth.new(ENV['FB_APP_ID'], ENV['FB_APP_SECRET'], "#{request.base_url}/callback")
    @oauth.get_app_access_token

    if !params[:post_since].nil? || !params[:page].nil?
      #TODO: 権限が無い場合に再度ログインを促す必要あり
      @graph = Koala::Facebook::API.new(session[:access_token], ENV['FB_APP_SECRET'])
      @permissions = @graph.get_connections("me", "permissions")
      @results = params[:page] ? @graph.get_page(JSON.parse(params[:page])) : @graph.get_connections("me", "posts", {since: params[:post_since], until: params[:post_until]})
    end

    erb :index
  end

  get '/login' do
    session[:oauth] = Koala::Facebook::OAuth.new(ENV['FB_APP_ID'], ENV['FB_APP_SECRET'], "#{request.base_url}/callback")
    redirect session[:oauth].url_for_oauth_code(:permissions => "user_posts,user_photos")
  end

  get '/logout' do
    session[:oauth] = nil
    session[:access_token] = nil
    redirect '/'
  end

  get '/callback' do
    session[:access_token] = session['oauth'].get_access_token(params[:code])
    redirect '/'
  end
end
