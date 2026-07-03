# Gem and file requirements

require 'sinatra'
require 'sinatra/content_for'
require 'tilt/erubi'

require_relative 'postgres_persistence'

# configure block(s)

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)
  set :erb, :escape_html => true
end

# This configure block runs only when RACK_ENV is 'development' (the default)
# :nocov:
# simplecov:disable
configure(:development) do
  require 'sinatra/reloader'
  also_reload 'postgres_persistence.rb'
  ## Assigns Sinatras settings hash a key :db_name with the name of the DEVELOPMENT reading_log database
  ## Store the database name, not the connection object
  set :db_name, 'reading_log'
end

# This configure block runs only when RACK_ENV is 'production'
configure(:production) do
  ## Assigns Sinatras settings hash a key :db_url with the URL for the PRODUCTION database ENV['DATABASE_URL']
  set :db_url, ENV['DATABASE_URL']
end
# simplecov:enable
# :nocov:

# This configure block runs only when RACK_ENV is 'test'
configure(:test) do
  ## For testing, we still want a single, persistent connection.
  ## Assigns Sinatras settings hash a key :db with the PG::Connect object from the TEST database
  set :db, PG.connect(dbname: 'reading_log_test')
end

# A helpers methods block goes here if I need one.  Right now I don't.

# Main application methods

def fetch_reader(reader_id)
  reader = @data.fetch_reader_data(reader_id).first # extract the one hash from the containing array
  return reader if reader

  session[:error] = 'The specified reader was not found.'
  redirect '/dashboard'
end

## Validation methods

def detect_invalid_input_for_pages_read(pages_read)
  # pages_read is an Integer
  # a non-digit value e.g. "a" input will have been converted to 0 by String#to_i in the POST "/reader/:reader_id" route
  # Therefore, this test checks for non-Integers AND Integers below zero

  return 'Pages read must be a valid number greater than zero.' if pages_read <= 0

  # Pages read shouldn't be higher than 999.  None of my kids read that much in one session!
  return 'There is no way you read that much in one go!' if pages_read > 999

  # If all checks pass, return nil (falsy, indicating no error).
  nil
end

def detect_duplicate_name_for_new_reader(reader_name)
  # Return a truthy value if reader_name IS a duplicate
  # AND has already been used in the readers.name column of the database

  # This method returns an array of all values in the readers.name database column
  names_list = @data.fetch_all_reader_names_as_array

  # Returns a truthy String if the new reader name is found in array of names i.e. the name is not unique.
  # Compares each name in names_list array with reader_name after whitespace stripped from that string
  names_list.include?(reader_name.strip)
end

def detect_invalid_input_for_new_reader_name(reader_name)
  # Check that reader_name is not empty i.e. ""
  return "Reader names can't be zero characters long or anonymous!" if reader_name.empty?

  # Check that reader_name is not too long max 25 chars
  return 'Reader names must be at most 25 characters.' if reader_name.length > 25

  # Check that reader_name is not a duplicate
  return 'This name already exists.  Choose another.' if detect_duplicate_name_for_new_reader(reader_name)

  nil # if input is valid, return nil/falsy value
end

def detect_invalid_input_for_session_date(session_date)
  # Checks that session_date is a String with the YYYY-MM-DD format
  # Use Regex to match.  =~ will return 0 if a match, nil otherwise
  unless session_date =~ /^([0-9]{4})-(1[0-2]|0[1-9])-(3[0-1]|0[1-9]|[1-2][0-9])$/
    return 'The reading session date must be in a string in the YYYY-MM-DD format.'
  end

  # Converts session_date to Date class object
  date = Date.parse(session_date)
  # Assigns today with a different Date object with today's date
  today = Date.today

  # Compares two Date class objects, date & today
  return "The reading session date can't be in the future." if date > today
  # Compares two Date class objects, date & today - 31 days
  return "The reading session date can't be more than 31 days ago." if date < (today - 31)

  nil # if input is valid, return nil/falsy value
end

# before and after blocks

before do
  db_connection = case settings.environment
                  when :test
                    # In test, use the persistent connection already created in the `configure` block
                    settings.db
                  # :nocov:
                  when :production
                    # In production, create a new connection using the URL
                    PG.connect(settings.db_url)
                  else # :development
                    # In development, create a new connection using the name
                    PG.connect(dbname: settings.db_name)
                  end
  # :nocov:

  # Instantiate the persistence object for this request
  @data = PostgresPersistence.new(db_connection, logger)
end

after do
  @data.disconnect unless ENV['RACK_ENV'] == 'test'
end

# Routes

get '/' do
  redirect '/dashboard'
end

get '/dashboard' do
  @dashboard_data = @data.fetch_all_data
  erb :dashboard, layout: :layout
end

get '/reader/add_reader' do
  erb :add_reader, layout: :layout
end

post '/reader/add_reader' do
  # Remove leading and trailing whitespace with String#strip
  reader_name = params[:reader_name].strip

  error = detect_invalid_input_for_new_reader_name(reader_name)

  if error # i.e. if error is truthy
    # Assigns one of many error message strings to session[:error]
    session[:error] = error
    # Return to add_reader view template and display error message on reload
    erb :add_reader, layout: :layout
  else # If error is nil i.e. falsy
    session[:success] = 'The new reader has been added.'
    @data.add_new_reader(reader_name)
    redirect '/dashboard'
  end
end

get '/reader/:reader_id' do
  # Type cast :reader_id from String to Integer as good practice
  reader_id = params[:reader_id].to_i
  @reader = fetch_reader(reader_id)
  erb :reader, layout: :layout
end

post '/reader/:reader_id' do
  # Type cast :reader_id and :pages_read from String to Integer as good practice
  reader_id = params[:reader_id].to_i
  pages_read = params[:pages_read].to_i
  # Date is ISO format YYYY-MM-DD String and doesn't need to be type cast
  session_date = params[:session_date]

  # Returns one of two error message strings or nil
  pages_read_error = detect_invalid_input_for_pages_read(pages_read)
  # Returns one of three error message strings or nil
  session_date_error = detect_invalid_input_for_session_date(session_date)

  if pages_read_error # If pages_read_error is truthy
    # Assigns one of two error message strings to session[:error]
    session[:error] = pages_read_error
    # Reassigns variables necessary to reload GET /reader/:reader_id
    @reader = fetch_reader(reader_id)
    erb :reader, layout: :layout
  elsif session_date_error # If session_date_error is truthy
    # Assigns one of two error message strings to session[:error]
    session[:error] = session_date_error
    # Reassigns variables necessary to reload GET /reader/:reader_id
    @reader = fetch_reader(reader_id)
    erb :reader, layout: :layout
  else # Ff both pages_read_error and session_date_error are nil i.e. falsy
    @data.log_reading_session(reader_id, pages_read, session_date)
    session[:success] = 'The reading session has been logged.'
    redirect "/reader/#{reader_id}"
  end
end

post '/reader/:reader_id/delete_reader' do
  # Name variable `id`` rather than `reader_id` to conform to database primary key for `readers` table
  id = params[:reader_id].to_i

  if [1, 2, 3, 4].include?(id) # Conditional logic to prevent my kids, niece and nephew deleting themselves!
    session[:error] = "Sorry.  I wrote this app for you. You can't delete your profile!"
    # reassigns variables necessary to reload GET /reader/:reader_id
    reader_id = params[:reader_id]
    @reader = fetch_reader(reader_id)
    erb :reader, layout: :layout
  else
    @data.delete_reader(id)
    session[:success] = 'That reader has been deleted.'
    redirect '/dashboard'
  end
end
