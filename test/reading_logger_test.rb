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
    db.exec("INSERT INTO readers (name) VALUES ('Simeon'), ('Rya'), ('Eshan'), ('Amiya'), ('User to be deleted');")
    
    # Summary of pages_read for sessions using this test data:
    # Simeon 
      ## today - 0
      ## yesterday - 20 - check the zero output on display from helper method
      ## 7 days - 35
      ## total - 100
    # Rya 
      ## today - 55
      ## yesterday - 0 - check the zero output on display from helper method
      ## 7 days - 405
      ## total - 450
    # Eshan
      ## no reading_sessions data
    # Amiya
      ## no reading_sessions data
    # 'User to be deleted'
      ## today - 99
      ## yesterday - 0
      ## 7 days - 99
      ## total - 99
      
    db.exec(
      "INSERT INTO reading_sessions (reader_id, session_date, pages_read)
      VALUES
      (1, CURRENT_DATE - INTERVAL '10 day', 65),
      (1, CURRENT_DATE - INTERVAL '2 day', 10),
      (1, CURRENT_DATE - INTERVAL '2 day', 5),
      (1, CURRENT_DATE - INTERVAL '1 day', 15),
      (1, CURRENT_DATE - INTERVAL '1 day', 5),
      (2, CURRENT_DATE - INTERVAL '99 day', 45),
      (2, CURRENT_DATE - INTERVAL '3 day', 100),
      (2, CURRENT_DATE - INTERVAL '3 day', 50),
      (2, CURRENT_DATE - INTERVAL '2 day', 200),
      (2, DEFAULT, 55),
      (5, DEFAULT, 99);"
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
    get "/reader/99"

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
    assert_includes last_response.body, "Pages read must be a valid number greater than zero."
    #### The route renders a view, not a redirect on error, so the status should be 200 (OK).
    assert_equal 200, last_response.status

    #### generate POST HTTP request to Rya/2 with numeric string input "-99"
    post "/reader/2", { pages_read: "-99" }
    #### Since the route renders a view on error, the status should be 200 (OK).
    assert_equal 200, last_response.status
    #### I expect a different error flash message in the body this time
    assert_includes last_response.body, "Pages read must be a valid number greater than zero."

    #### generate POST HTTP request to Rya/2 with numeric string input "1000"
    post "/reader/2", { pages_read: "1000" }
    #### Since the route renders a view on error, the status should be 200 (OK).
    assert_equal 200, last_response.status
    #### I expect a different error flash message in the body this time
    assert_includes last_response.body, "There is no way you read that much in one go!"
  end

  ### test valid input does update the database

  def test_valid_input_to_pages_read_for_reader1_simeon
    #### generate POST HTTP request to Simeon/1 with numeric input "500"
    post "/reader/1", { pages_read: "500" }

    #### The route redirects without error, so the status should be 302 (OK).
    assert_equal 302, last_response.status
    #### The route redirects to `GET /reader/1`
    assert_equal "http://example.org/reader/1", last_response.headers['location']

    #### Check data logic in the POST route
    #### Simeon's Pages Today are now 500

    db = PG.connect(dbname: "reading_log_test")
    sql = <<~SQL
      SELECT SUM(pages_read) 
      FROM reading_sessions 
      WHERE reader_id = $1 AND session_date = CURRENT_DATE;
    SQL
  
    result = db.exec_params(sql, [1])
    pages_today = result.getvalue(0, 0).to_i # .getvalue(row, col) is useful for retrieving single values from PG::Result objects
    db.close # Important: close the connection

    #### Simeon's 7 days pages are now 535
    db = PG.connect(dbname: "reading_log_test")
    sql = <<~SQL
      SELECT SUM(pages_read) 
      FROM reading_sessions 
      WHERE reader_id = $1 
        AND session_date BETWEEN CURRENT_DATE - INTERVAL '7 days' AND CURRENT_DATE;
    SQL
    result = db.exec_params(sql, [1])
    pages_7_days = result.getvalue(0, 0).to_i # .getvalue(row, col) is useful for retrieving single values from PG::Result objects
    db.close # Important: close the connection
    assert_equal 535, pages_7_days

    #### Simeon's Total Pages are now 600
    db = PG.connect(dbname: "reading_log_test")
    sql = <<~SQL
      SELECT SUM(pages_read) 
      FROM reading_sessions 
      WHERE reader_id = $1;
    SQL

    result = db.exec_params(sql, [1])
    total_pages = result.getvalue(0, 0).to_i

    assert_equal 600, total_pages

    db.close # Important: close the connection
    
    #### Success flash message assigned to session[:success]
    assert_equal "The reading session has been logged.", session[:success]

    #### Check presentation logic in the resulting GET route
    ##### make redirect request then examine the last_request.body for the same values as above
    #### Check presentation logic in the resulting GET route
    get last_response["Location"]
    assert_includes last_response.body, "600" # 600 total pages read
    assert_includes last_response.body, "535" # 535 pages read in last 7 days
    assert_includes last_response.body, "500" # 500 pages read today
  end

  def test_valid_input_to_pages_read_for_reader2_rya
    #### generate POST HTTP request to Rya/2 with numeric input "50"
    post "/reader/2", { pages_read: "50" }

    #### The route redirects without error, so the status should be 302 (OK).
    assert_equal 302, last_response.status
    #### The route redirects to `GET /reader/2`
    assert_equal "http://example.org/reader/2", last_response.headers['location']
    #### Success flash message assigned to session[:success]
    assert_equal "The reading session has been logged.", session[:success]

    #### Check data logic in the POST route

    #### Rya's Pages Today are now 105

    db = PG.connect(dbname: "reading_log_test")
    sql = <<~SQL
      SELECT SUM(pages_read) 
      FROM reading_sessions 
      WHERE reader_id = $1 AND session_date = CURRENT_DATE;
    SQL
  
    result = db.exec_params(sql, [2])
    pages_today = result.getvalue(0, 0).to_i # .getvalue(row, col) is useful for retrieving single values from PG::Result objects
    db.close # Important: close the connection

    #### Rya's 7 days pages are now 455
    db = PG.connect(dbname: "reading_log_test")
    sql = <<~SQL
      SELECT SUM(pages_read) 
      FROM reading_sessions 
      WHERE reader_id = $1 
        AND session_date BETWEEN CURRENT_DATE - INTERVAL '7 days' AND CURRENT_DATE;
    SQL

    result = db.exec_params(sql, [2])
    pages_7_days = result.getvalue(0, 0).to_i # .getvalue(row, col) is useful for retrieving single values from PG::Result objects
    db.close # Important: close the connection
    assert_equal 455, pages_7_days

    #### Simeon's Total Pages are now 500
    db = PG.connect(dbname: "reading_log_test")
    sql = <<~SQL
      SELECT SUM(pages_read) 
      FROM reading_sessions 
      WHERE reader_id = $1;
    SQL

    result = db.exec_params(sql, [2])
    total_pages = result.getvalue(0, 0).to_i

    assert_equal 500, total_pages

    db.close # Important: close the connection

    #### Check presentation logic in the resulting GET route
    ##### make redirect request then examine the last_request.body for the same values as above
    get last_response["Location"]
    assert_includes last_response.body, "500" # 500 total pages read
    assert_includes last_response.body, "455" # 455 pages read in last 7 days
    assert_includes last_response.body, "105" # 105 pages read today
  end

  ## get /reader/add_reader
  def test_add_reader_view_displays_expected
    get "/reader/add_reader"

    assert_equal 200, last_response.status
    # Test part of expected view template - this is currently failing WHY?
    assert_includes last_response.body, "<p>Enter name of reader:</p>","Expected view template content not rendered"
  end

  ## post /reader/add_reader

  ### test invalid input raises flash messages and does not update the database

  def test_invalid_input_to_name_of_new_reader
    #### empty string
    post "/reader/add_reader", { reader_name: "" }

    ##### The route renders a view, not a redirect on error, so the status should be 200 (OK).
    assert_equal 200, last_response.status
    ##### Correct error flash message included in the body
    assert_includes last_response.body, "Reader names can&#39;t be zero characters long or anonymous!"

    #### String longer than 25 characters (I'm using 30)
    post "/reader/add_reader", { reader_name: "abcdefghijklmnopqrstuvwxyz!?<>" }

    ##### The route renders a view, not a redirect on error, so the status should be 200 (OK).
    assert_equal 200, last_response.status
    ##### Correct error flash message included in the body
    assert_includes last_response.body, "Reader names must be at most 25 characters." 

    #### duplicate name already in use
    post "/reader/add_reader", { reader_name: "Simeon" }
    ##### The route renders a view, not a redirect on error, so the status should be 200 (OK).
    assert_equal 200, last_response.status

    ##### Correct error flash message included in the body
    assert_includes last_response.body, "This name already exists.  Choose another."
  end

  ### test valid input does update the database

  def test_valid_input_to_name_of_new_reader
    post "/reader/add_reader", { reader_name: "Graham" }

    #### The route redirects without error, so the status should be 302 (OK).
    assert_equal 302, last_response.status
    #### The route redirects to `GET /dashboard`
    assert_equal "http://example.org/dashboard", last_response.headers['location']
    #### Success flash message assigned to session[:success]
    assert_equal "The new reader has been added.", session[:success]
    
    #### Check data logic in the POST route

    db = PG.connect(dbname: "reading_log_test")
    sql = <<~SQL
      SELECT name
      FROM readers
      WHERE id = $1;
    SQL
  
    result = db.exec_params(sql, [6])
    new_name = result.getvalue(0, 0) # .getvalue(row, col) is useful for retrieving single values from PG::Result objects
    db.close # Important: close the connection

    assert_equal new_name, "Graham"

    #### Check presentation logic in the resulting GET route
    get last_response["Location"]
    assert_includes last_response.body, "Graham" # new name present in dashboard
  end


  ## post /reader/:reader_id/delete_reader

  ### test valid input does update the database

  def test_reader_can_be_deleted
    post "/reader/5/delete_reader" # explicitly call the route with :reader_id i.e. not post "/reader/:reader_id/delete_reader, { reader_id: "5" }"

    ##### The route redirects to `GET /dashboard`
    assert_equal "http://example.org/dashboard", last_response.headers['location']
    ##### The route redirects without error, so the status should be 302 (OK).
    assert_equal 302, last_response.status
    ##### Correct error flash message included in the session
    assert_equal "That reader has been deleted.", session[:success]

    #### Check data logic in the POST route
    db = PG.connect(dbname: "reading_log_test")
    sql = <<~SQL
      SELECT name
      FROM readers
      WHERE id = $1;
    SQL
    result = db.exec_params(sql, [5])
    db.close # Important: close the connection

    ##### deleted reader id 5 should be gone now and so the results set from the above query should contain no rows at all
    assert_equal 0, result.ntuples

    #### Check presentation logic in the resulting GET route
    get last_response["Location"]
    ##### This user should be gone from the dashboard now
    refute_includes last_response.body, "User to be deleted" 
  end

  def test_protected_reader_simeon_1_cannot_be_deleted
    post "/reader/1/delete_reader"
    
    #### The route renders a view, not a redirect on error, so the status should be 200 (OK).
    assert_equal 200, last_response.status

    #### Correct error flash message included in the body
    assert_includes last_response.body, "Sorry.  I wrote this app for you. You can&#39;t delete your profile!"
  end

  def test_protected_reader_amiya_4_cannot_be_deleted
    post "/reader/4/delete_reader"
    #### The route renders a view, not a redirect on error, so the status should be 200 (OK).
    assert_equal 200, last_response.status

    #### Correct error flash message included in the body
    assert_includes last_response.body, "Sorry.  I wrote this app for you. You can&#39;t delete your profile!"
  end

end