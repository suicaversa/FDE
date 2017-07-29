require 'bundler'
Bundler.require(:default, ENV['RACK_ENV'].to_sym)
Dotenv.load

class SNSDataExtractor < Sinatra::Application
  use Rack::Session::Cookie, secret: ENV['SESSION_SECRET']

  get '/' do
    @oauth = Koala::Facebook::OAuth.new(ENV['FB_APP_ID'], ENV['FB_APP_SECRET'], "#{request.base_url}/callback")
    @oauth.get_app_access_token
    erb :index
  end

  get '/login' do
    session['oauth'] = Koala::Facebook::OAuth.new(ENV['FB_APP_ID'], ENV['FB_APP_SECRET'], "#{request.base_url}/callback")
    redirect session['oauth'].url_for_oauth_code()
  end

  get '/logout' do
    session['oauth'] = nil
    session['access_token'] = nil
    redirect '/'
  end

  get '/callback' do
    session['access_token'] = session['oauth'].get_access_token(params[:code])
    redirect '/'
  end
end
