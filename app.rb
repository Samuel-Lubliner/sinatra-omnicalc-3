require "sinatra"
require "sinatra/reloader"
require "http"
require "sinatra/cookies"
require "json"


get("/") do
  erb(:umbrella_form)
end

get("/umbrella") do
  erb(:umbrella_form)
end

post("/process_umbrella") do
  @user_location = params.fetch("user_loc")

  url_encoded_string = @user_location.gsub(" ", "+")

  gmaps_key = ENV.fetch("GMAPS_KEY")

  gmaps_url = "https://maps.googleapis.com/maps/api/geocode/json?address=#{url_encoded_string}&key=#{gmaps_key}"

  raw_response = HTTP.get(gmaps_url).to_s

  parsed_response = JSON.parse(raw_response)

  loc_hash = parsed_response.dig("results", 0, "geometry", "location")

  @latitude = loc_hash.fetch("lat")
  @longitude = loc_hash.fetch("lng")

  pirate_weather_key = ENV.fetch("PIRATE_WEATHER_KEY")

  pirate_weather_url = "https://api.pirateweather.net/forecast/#{pirate_weather_key}/#{@latitude},#{@longitude}"

  raw_pirate_weather_data = HTTP.get(pirate_weather_url)

  parsed_pirate_weather_data = JSON.parse(raw_pirate_weather_data)

  currently_hash = parsed_pirate_weather_data.fetch("currently")

  @current_temp = currently_hash.fetch("temperature")

  minutely_hash = parsed_pirate_weather_data.fetch("minutely", false)

if minutely_hash
  next_hour_summary = minutely_hash.fetch("summary")

  @summary = next_hour_summary
end

hourly_hash = parsed_pirate_weather_data.fetch("hourly")

hourly_data_array = hourly_hash.fetch("data")

next_twelve_hours = hourly_data_array[1..12]

precip_prob_threshold = 0.10

any_precipitation = false

next_twelve_hours.each do |hour_hash|
  precip_prob = hour_hash.fetch("precipProbability")

  if precip_prob > precip_prob_threshold
    any_precipitation = true

    precip_time = Time.at(hour_hash.fetch("time"))

    seconds_from_now = precip_time - Time.now

    hours_from_now = seconds_from_now / 60 / 60

    @rain_summ = "In #{hours_from_now.round} hours, there is a #{(precip_prob * 100).round}% chance of precipitation."
  end
end

if any_precipitation == true
  @umbrella = "You might want to take an umbrella!"
else
  @umbrella = "You probably won't need an umbrella."
end
  erb(:umbrella_results)
end

get("/message") do
  erb :message_form
end

post("/process_single_message") do
  @user_message = params['user_message']

  # Prepare the request to OpenAI API
  request_headers_hash = {
    "Authorization" => "Bearer #{ENV.fetch("GPTKEY")}",
    "content-type" => "application/json"
  }

  request_body_hash = {
    "model" => "gpt-3.5-turbo",
    "messages" => [
      {
        "role" => "system",
        "content" => "You are an assistant who responds in a simple and clear way."
      },
      {
        "role" => "user",
        "content" => @user_message
      }
    ]
  }

  request_body_json = JSON.generate(request_body_hash)

  raw_response = HTTP.headers(request_headers_hash).post(
    "https://api.openai.com/v1/chat/completions",
    :body => request_body_json
  ).to_s

  parsed_response = JSON.parse(raw_response)
  @gpt_response = parsed_response['choices'][0]['message']['content']

  erb :message_response
end

get("/chat") do
  @chat_history = request.cookies["chat_history"] ? JSON.parse(request.cookies["chat_history"]) : []
  erb :chat
end

post("/add_message_to_chat") do
  user_message = params['user_message']
  
  request_headers_hash = {
    "Authorization" => "Bearer #{ENV.fetch("GPTKEY")}",
    "content-type" => "application/json"
  }

  request_body_hash = {
    "model" => "gpt-3.5-turbo",
    "messages" => [
      {
        "role" => "system",
        "content" => "You are an assistant who responds in a simple and clear way."
      },
      {
        "role" => "user",
        "content" => user_message
      }
    ]
  }

  request_body_json = JSON.generate(request_body_hash)
  
  raw_response = HTTP.headers(request_headers_hash).post(
    "https://api.openai.com/v1/chat/completions",
    :body => request_body_json
  ).to_s

  parsed_response = JSON.parse(raw_response)
  gpt_response = parsed_response['choices'][0]['message']['content']

  # Save chat history to cookies
  chat_history = request.cookies["chat_history"] ? JSON.parse(request.cookies["chat_history"]) : []
  chat_history.push({"role" => "user", "message" => user_message})
  chat_history.push({"role" => "assistant", "message" => gpt_response})

  response.set_cookie("chat_history", chat_history.to_json)

  redirect "/chat"
end

post("/clear_chat") do
  response.delete_cookie("chat_history")
  redirect "/chat"
end
