require 'simplecov'
SimpleCov.start

ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "pg"

require_relative "../reading_logger.rb"
# load 'reading_logger.rb' # might be better than require_relative to avoid "ghost in the machine" bug issues

class ReadingLoggerTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  # helper method to provide access to the session hash from the last HTTP request
  def session
    last_request.env["rack.session"]
  end

  # This method runs before each test.
def setup
    # I need a connection to the test database to prepare it.
    # I will create and close the connection it inside `setup` to ensure it's fresh for each test and it doesn't conflict with the application's own connection.
    db = PG.connect(dbname: "reading_log_test")

    # Clear out any existing data before each test
    db.exec("TRUNCATE readers, reading_sessions RESTART IDENTITY;")

    # Add test data for every test
    db.exec("INSERT INTO readers (name) VALUES ('Simeon'), ('Rya');")
    
    # Summary of pages_read for sessions using this test data:
    # Simeon 
      ## today - 0
      ## yesterday - 20 - check the zero output on display from helper method
      ## 7 days - 40
      ## total - 100
    # Rya 
      ## today - 55
      ## yesterday - 0 - check the zero output on display from helper method
      ## 7 days - 405
      ## total - 450
    db.exec(
      "INSERT INTO reading_sessions (reader_id, session_date, pages_read)
      VALUES
      (1, CURRENT_DATE - INTERVAL '10 day', 60),
      (1, CURRENT_DATE - INTERVAL '2 day', 10),
      (1, CURRENT_DATE - INTERVAL '2 day', 5),
      (1, CURRENT_DATE - INTERVAL '1 day', 15),
      (1, CURRENT_DATE - INTERVAL '1 day', 5),
      (2, CURRENT_DATE - INTERVAL '99 day', 45),
      (2, CURRENT_DATE - INTERVAL '3 day', 100),
      (2, CURRENT_DATE - INTERVAL '3 day', 50),
      (2, CURRENT_DATE - INTERVAL '2 day', 200),
      (2, DEFAULT, 55);"
    )

    db.close # Close the setup-specific connection
  end

  # NO TEARDOWN!  This method would normally run after each test.
  
  # TESTS GO HERE - I've categorised by route
  # Tests should test the final HTTP response, not the content of internal variables

  ## get /

  ### test home page redirects to /dashboard
  def test_homepage_redirect_to_dashboard
    get "/"

    # redirect status code 302, not 200 or other
    assert_equal 302, last_response.status
    # redirected to /dashboard and nowhere else
    assert_equal "http://example.org/dashboard", last_response.headers['location']
  end

  ## get /dashboard

  ### test dashboard displays the test data from the setup

  def test_dashboard_displays_reader_data
    get "/dashboard"

    assert_equal 200, last_response.status
    #### Check that the names of the readers we inserted in `setup` appear on the page
    assert_includes last_response.body, "Simeon"
    assert_includes last_response.body, "Rya"
    #### Check that some of the data (e.g., total_pages_read) is calculated and    played
    ##### Simeon's expected display
    assert_includes last_response.body, "0", "Todays pages for Simeon is incorrect or missing"
    assert_includes last_response.body, "20", "Yesterdays pages for Simeon is incorrect or missing"
    assert_includes last_response.body, "40", "7 days pages for Simeon is incorrect or missing" 
    assert_includes last_response.body, "100", "Total pages for Simeon is incorrect or missing" 
    ##### Rya's expected display
    assert_includes last_response.body, "55", "Todays pages for Rya is incorrect or missing"
    ###### (Can't test "0" for yesterday, because it is expected for Simeon's today value)
    assert_includes last_response.body, "405", "7 days pages for Rya is incorrect or missing" 
    assert_includes last_response.body, "450", "Correct total_pages for Rya is missing"
  end

  ## get /reader/:id

  ### test reader view displayes the test data from the setup

  def test_reader_view_displays_reader_data
    get "/reader/1"

    assert_equal 200, last_response.status
    #### Check that the name of the correct reader is displayed
    assert_includes last_response.body, "Simeon"
    #### Check that the correct data is displayed
    ##### Simeon's expected display
    assert_includes last_response.body, "0", "Todays pages for Simeon is incorrect or missing"
    assert_includes last_response.body, "20", "Yesterdays pages for Simeon is incorrect or missing"
    assert_includes last_response.body, "40", "7 days pages for Simeon is incorrect or missing" 
    assert_includes last_response.body, "100", "Total pages for Simeon is incorrect or missing" 

    get "/reader/2"

    assert_equal 200, last_response.status
    #### Check that the name of the correct reader is displayed
    assert_includes last_response.body, "Rya"
    #### Check that the correct data is displayed
    assert_includes last_response.body, "55", "Todays pages for Rya is incorrect or missing"
    assert_includes last_response.body, "0", "Yesterdays pages for Rya is incorrect or missing"
    assert_includes last_response.body, "405", "7 days pages for Rya is incorrect or missing" 
    assert_includes last_response.body, "450", "Correct total_pages for Rya is missing"
  end

  ### test invalid :reader_id that doesn't match the test database readers table records

  def test_reader_view_invalid_reader
    get "/reader/3"

    #### redirect to get /dashboard
    assert_equal "http://example.org/dashboard", last_response.headers['location']
    #### redirect status is 302 not 200
    assert_equal 302, last_response.status
    #### The error message is stored in the session, which I can access using my helper `session` method above.  session[:error] should be "The specified reader was not found."  This works because the route ends in a redirect not a reload of the same page view.
    assert_equal session[:error], "The specified reader was not found."
  end

  ## post "/reader/:reader_id"

  ### test invalid input raises flash messages and does not update the database

  def test_invalid_input_to_pages_read
    #### generate POST HTTP request to Simeon/1 with alphabetic input "a"
    post "/reader/1", { pages_read: "a" }
    
    #### The error message is stored in the session, not the response headers.  But the session[:error] is deleted immediately by the code in the view template, so it is not accessible with this reload of the same page.   Instead I will check that the response body shows the flash error message to the user.
    assert_includes last_response.body, "Pages read must be a valid number."
    #### The route renders a view, not a redirect on error, so the status should be 200 (OK).
    assert_equal 200, last_response.status

    #### generate POST HTTP request to Rya/2 with numeric string input "-99"
    post "/reader/2", { pages_read: "-99" }
    #### Since the route renders a view on error, the status should be 200 (OK).
    assert_equal 200, last_response.status
    #### I expect a different error flash message in the body this time
    assert_includes last_response.body, "Pages read must be a number greater than zero."
  end

  ### test valid input does update the database

  def test_valid_input_to_pages_read
    #### generate POST HTTP request to Simeon/1 with numeric input "500"
    post "/reader/1", { pages_read: "500" }

    #### The route redirects without error, so the status should be 302 (OK).
    assert_equal 302, last_response.status
    #### The route redirects to `GET /reader/1`
    assert_equal "http://example.org/reader/1", last_response.headers['location']
    #### Simeon's Total Pages are now 600
    assert_includes "600", last_response.body
    #### Simeon's Pages Today are now 500
    assert_includes "500", last_response.body
    #### Success flash message assigned to session[:success]
    assert_equal "The reading session has been logged.", session[:success]

    #### generate POST HTTP request to Rya/2 with numeric input "50"
    post "/reader/2", { pages_read: "50" }

    #### The route redirects without error, so the status should be 302 (OK).
    assert_equal 302, last_response.status
    #### The route redirects to `GET /reader/2`
    assert_equal "http://example.org/reader/2", last_response.headers['location']
    #### Rya's Total Pages are now 500
    assert_includes "500", last_response.body
    #### Rya's Pages Today are now 500
    assert_includes "105", last_response.body
    #### Success flash message assigned to session[:success]
    assert_equal "The reading session has been logged.", session[:success]  
  end

end