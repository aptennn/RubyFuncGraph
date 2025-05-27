
require 'sinatra'
require 'sinatra/reloader' if development?
require 'base64'
require 'dentaku'
require 'gruff'

configure do
  set :public_folder, File.dirname(__FILE__) + '/public'
end

get '/' do
  erb :form
end

post '/submit' do
  @function = params[:user_input].strip

  begin
    unless safe_expression?(@function)
      raise "Недопустимые символы в функции"
    end

    case params[:action]
    when 'function'
      @graph = plot_function(@function)
    when 'derivative'
      @graph = plot_derivative(@function)
    when 'integral'
      @graph = plot_integral(@function)
    end
  rescue => e
    @error = "Ошибка: #{e.message}. Попробуйте: x**2, sin(x), 2*x + 1"
  end

  erb :form
end

helpers do
  def safe_expression?(expr)
    # Разрешаем стандартные математические функции без Math.
    expr.match?(/^[\d\sxX\+\-\*\/\.,\(\)\^sin|cos|tan|sqrt|log|exp]+$/i)
  end

  def calculate_expression(expr, x_val)
    expr = expr.downcase

    # Поддержка x^2 как x**2
    expr = expr.gsub(/\^/, '**')

    # Добавим Math. к математическим функциям
    expr = expr.gsub(/(?<!Math\.)(sin|cos|tan|sqrt|log|exp)\(/, 'Math.\1(')

    # Защита от небезопасных конструкций
    unless expr.match?(/\A[\d\s\.\+\-\*\/\(\)xX\^a-zA-Z_]*\z/)
      raise "Недопустимые символы"
    end

    x = x_val # подставляем x
    result = eval(expr)
    result.is_a?(Numeric) ? result : Float::NAN
  rescue
    Float::NAN
  end


  def plot_function(function_string)
    x, y = [], []

    (-10.0..10.0).step(0.1) do |i|
      begin
        result = calculate_expression(function_string, i)
        next if result.nil? || result.nan?

        x << i.round(2)
        y << result
      rescue
        next
      end
    end

    save_plot_to_base64(x, y, "График функции: #{function_string}", "f(x)")
  end

  def plot_derivative(function_string)
    x1, y1 = [], []
    h = 0.01

    (-10.0..10.0).step(0.1) do |i|
      begin
        f_x = calculate_expression(function_string, i)
        f_xh = calculate_expression(function_string, i + h)
        next if f_x.nil? || f_xh.nil? || f_x.nan? || f_xh.nan?

        x1 << i.round(2)
        y1 << (f_xh - f_x) / h
      rescue
        next
      end
    end

    save_plot_to_base64(x1, y1, "Производная функции для графика: #{function_string}", "f'(X)")
  end

  def plot_integral(function_string)
    x1, y1 = [], []
    integral = 0.0

    (-10.0..10.0).step(0.1) do |i|
      begin
        f_x = calculate_expression(function_string, i)
        next if f_x.nil? || f_x.nan?

        integral += f_x * 0.1
        x1 << i.round(2)
        y1 << integral
      rescue
        next
      end
    end

    save_plot_to_base64(x1,y1, "Интеграл функции: #{function_string}", "∫f(x)dx")
  end


  def save_plot_to_base64(x, y, title, label)
    gruff = Gruff::Line.new(800)
    gruff.title = title

    # Упрощаем метки X, иначе их будет слишком много
    labels = {}
    x.each_with_index do |val, i|
      labels[i] = val.to_s if i % 20 == 0
    end
    gruff.labels = labels

    gruff.data(label, y)

    temp_file = "temp_plot_#{Time.now.to_i}.png"
    gruff.write(temp_file)
    image_base64 = Base64.strict_encode64(File.read(temp_file))
    File.delete(temp_file)
    "data:image/png;base64,#{image_base64}"
  rescue => e
    raise "Ошибка при создании графика: #{e.message}"
  end

end