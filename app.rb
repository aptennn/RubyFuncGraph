require 'sinatra'
require 'sinatra/reloader' if development?
require 'gnuplot'
require 'fileutils'

configure do
  set :public_folder, File.dirname(__FILE__) + '/public'
  def find_gnuplot
    if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
      path = `where gnuplot 2>NUL`.strip
      return "\"#{path}\"" unless path.empty?
    else
      path = `which gnuplot`.strip
      return path unless path.empty?
    end
    raise "Gnuplot не найден в PATH. Убедитесь, что он установлен и добавлен в системные переменные."
  end

  set :gnuplot_path, find_gnuplot
end

get '/' do
  erb :form
end

post '/submit' do
  @function = params[:user_input].strip
  @mode = params[:action]
  @error = nil

  begin
    raise "Недопустимые символы в функции" unless safe_expression?(@function)

    case @mode
    when 'function'
      generate_plot_png(@function)
    when 'derivative'
      generate_plot_png(@function, mode: :derivative)
    when 'integral'
      generate_plot_png(@function, mode: :integral)
    else
      raise "Неизвестный режим"
    end

    @graph_path = '/plot.png'
  rescue => e
    @error = "Ошибка: #{e.message}. Примеры: x**2 + y**2, sin(x*y), sin(sqrt(x**2 + y**2))"
  end

  erb :form
end

helpers do
  def safe_expression?(expr)
    expr.match?(/^[\d\sxyXY\+\-\*\/\.,\(\)\^a-z]+$/i)
  end

  def calculate_expression(expr, x_val, y_val)
    expr = expr.downcase.gsub(/\^/, '**')
    expr = expr.gsub(/(?<!Math\.)(sin|cos|tan|sqrt|log|exp)\(/, 'Math.\1(')

    x = x_val
    y = y_val
    val = eval(expr)
    val.is_a?(Numeric) ? val : Float::NAN
  rescue
    Float::NAN
  end

  def generate_plot_png(function_string, mode: :function)
    require 'tempfile'

    x_vals = (-10.0).step(10.0, 0.5).to_a
    y_vals = (-10.0).step(10.0, 0.5).to_a
    h = 0.01
    data = []
    title = case mode
            when :function then "3D-график f(x,y)"
            when :derivative then "Производная по x"
            when :integral then "Интеграл по x"
            end

    y_vals.each do |y|
      row = []
      integral = 0.0

      x_vals.each_with_index do |x, i|
        begin
          val =
            case mode
            when :function
              calculate_expression(function_string, x, y)
            when :derivative
              f_x = calculate_expression(function_string, x, y)
              f_xh = calculate_expression(function_string, x + h, y)
              (f_xh - f_x) / h
            when :integral
              fx = calculate_expression(function_string, x, y)
              integral += fx * 0.5
              integral
            end

          row << (val.nan? ? "NaN" : val.round(4))
        rescue
          row << "NaN"
        end
      end

      data << row
    end

    output_path = File.join(settings.public_folder, "plot.png")

    Tempfile.create(['gnuplot_data', '.dat']) do |datafile|
      Tempfile.create(['gnuplot_script', '.gp']) do |scriptfile|

        x_vals.each_with_index do |x, i|
          y_vals.each_with_index do |y, j|
            z = data[j][i]
            datafile.puts "#{x} #{y} #{z}"
          end
        end
        datafile.flush

        scriptfile.write(<<~GNUPLOT)
          set terminal pngcairo size 800,600 enhanced
          set output "#{output_path.gsub('\\', '/')}"
          set title "#{title}"
          set xlabel "X"
          set ylabel "Y"
          set zlabel "Z"
          set hidden3d
          splot "#{datafile.path.gsub('\\', '/')}" using 1:2:3 with lines notitle
        GNUPLOT
        scriptfile.flush

        result = system(%Q(#{settings.gnuplot_path} "#{scriptfile.path}"))
        raise "Gnuplot не выполнился" unless result
        raise "Файл не создан" unless File.exist?(output_path)
      end
    end
  end
end
