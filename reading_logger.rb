# gem and file requirements

require "sinatra"
require "sinatra/content_for"
require "tilt/erubi"

require_relative "postgres_persistence.rb"

# configure block(s)

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)
  set :erb, :escape_html => true
end

# This runs only when RACK_ENV is 'development' (the default)

# :nocov:
# simplecov:disable
configure(:development) do
  require "sinatra/reloader"
  also_reload "postgres_persistence.rb"
  # Assigns Sinatras settings hash a key :db_name with the name of the DEVELOPMENT reading_log database
  # Store the database name, not the connection object
  set :db_name, "reading_log"
end


# This runs only when RACK_ENV is 'production'
configure :production do
  # Heroku and other providers set a DATABASE_URL environment variable
  db = PG.connect(ENV['DATABASE_URL'])
  # Assigns Sinatras settings hash a key :db_url with the URL for the PRODUCTION database ENV['DATABASE_URL']
  set :db_url, ENV['DATABASE_URL']
end
# simplecov:enable
# :nocov:

# This runs only when RACK_ENV is 'test'
configure(:test) do
  # For testing, we still want a single, persistent connection.  Assigns Sinatras settings hash a key :db with the PG::Connect object from the TEST database
  set :db, PG.connect(dbname: "reading_log_test")
end
# helpers methods block

# helpers do

  # method to sort the hashes in the @data array in some order?  Like ordering by reader with most pages read?  Or the date order in which reader last added sessions? (Although that seems quite hard to do)
  
# end

# main application methods

def fetch_reader(reader_id)
  reader = @data.fetch_reader_data(reader_id).first # extract the one hash from the containing array
  return reader if reader

  session[:error] = "The specified reader was not found."
  redirect "/dashboard"
end

## helper validation methods

def detect_invalid_input_for_pages_read(pages_read_string)
  # Check if the string is not a numeric String.  The `to_i` method on a string like "a" returns 0, so "a".to_i.to_s == "0", not "a".
  return "Pages read must be a valid number." if pages_read_string.to_i.to_s != pages_read_string

  # Now that we know it's a number, check if it's positive.
  return "Pages read must be a number greater than zero." if pages_read_string.to_i <= 0

  # Pages read shouldn't be higher than 999.  None of my kids read that much in one session!
  return "There is no way you read that much in one go!" if pages_read_string.to_i > 999

  # If all checks pass, return nil (falsy, indicating no error).
  nil
end

def detect_duplicate_name_for_new_reader(reader_name)
  # return truthy value if reader_name IS a duplicate and has already been used in the readers.name column of the database
  
  # this method returns an array of all values in the readers.name database column
  names_list = @data.get_all_reader_names_as_array

  # returns truthy string if the new reader name is found in array of names i.e. is not unique.  Compares each name in names_list array with reader_name after whitespace stripped from that string
  names_list.include?(reader_name.strip)
end

def detect_invalid_input_for_new_reader_name(reader_name)
  # Check that reader_name is not empty i.e. ""
  return "Reader names can't be zero characters long or anonymous!" if reader_name.empty?

  # Check that reader_name is not too long max 25 chars
  return "Reader names must be at most 25 characters." if reader_name.length > 25

  # Check that reader_name is not a duplicate
  return "This name already exists.  Choose another." if detect_duplicate_name_for_new_reader(reader_name)

  #

  nil
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
  @data.disconnect unless ENV["RACK_ENV"] == "test"
end

# routes

get "/" do
  redirect "/dashboard"
end

get "/dashboard" do
  @dashboard_data = @data.fetch_all_data
  erb :dashboard, layout: :layout
end

get "/reader/add_reader" do
  erb :add_reader, layout: :layout
end

post "/reader/add_reader" do
  # remove leading and trailing whitespace with String#strip
  reader_name = params[:reader_name].strip

  error = detect_invalid_input_for_new_reader_name(reader_name)

  if error # error is truth
    # assigns one of many error message strings to session[:error]
    session[:error] = error
    # return to add_reader view template and display error message on reload
    erb :add_reader, layout: :layout
  else # if error is nil i.e. falsy
    session[:success] = "The new reader has been added."
    @data.add_new_reader(reader_name)
    redirect "/dashboard"
  end
end

get "/reader/:reader_id" do
  # do I need to type cast :reader_id and :pages_read?  If not, why?
  reader_id = params[:reader_id]
  @reader = fetch_reader(reader_id)
  erb :reader, layout: :layout
end

post "/reader/:reader_id" do
  reader_id = params[:reader_id]
  pages_read = params[:pages_read] # use this for name of corresponding field from form in view template
  
  # returns one of two error message strings or nil
  error = detect_invalid_input_for_pages_read(pages_read)

  if error # if error is truthy
    # assigns one of two error message strings to session[:error]
    session[:error] = error
    # reassigns variables necessary to reload GET /reader/:reader_id
    reader_id = params[:reader_id]
    @reader = fetch_reader(reader_id)
    erb :reader, layout: :layout
  else # if error is nil i.e. falsy
    # I type cast :reader_id and :pages_read from Strings to Integers here
    @data.log_reading_session(reader_id.to_i, pages_read.to_i)
    session[:success] = "The reading session has been logged."
    redirect "/reader/#{reader_id}"
  end
end

post "/reader/:reader_id/delete_reader" do
  id = params[:reader_id].to_i # id rather than reader_id to conform to database primary key for `readers` table

  if [1, 2, 3, 4].include?(id) # conditional logic to prevent my kids, niece and nephew deleting themselves!
    session[:error] = "Sorry.  I wrote this app for you. You can't delete your profile!"
    # reassigns variables necessary to reload GET /reader/:reader_id
    reader_id = params[:reader_id]
    @reader = fetch_reader(reader_id)
    erb :reader, layout: :layout
  else
    @data.delete_reader(id)
    session[:success] = "That reader has been deleted."
    redirect "/dashboard"
  end
end
