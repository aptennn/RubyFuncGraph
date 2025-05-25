require "sinatra"

get '/' do
  erb :form
end

post '/submit' do
  @function = params[:user_input]
  action = params[:action]

  # TODO: логика для генерации графика (присвоить график переменной @graph)
  erb :form
end