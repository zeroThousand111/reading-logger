require 'pg'

class PostgresPersistence
  def initialize(db_connection, logger)
    # Assign the passed-in db_connection to an instance variable
    # This is a Sinatra setting decided upon by which environment the app is in i.e. development, production or testing
    @db = db_connection 
    @logger = logger
  end

  def query(statement, *params)
    # presuming I will use Sinatra's logger functionality for debugging
    @logger.info("#{statement} | #{params}")
    # the main connection method
    @db.exec_params(statement, params)
  end

  # helper methods

  def transform_nil_values_to_zero(value)
    if value.nil?
      "0" 
    else 
      value
    end
  end

  def transform_result_object_to_data_structure(result)
    # do the numeric String values need to be Integers?  Maybe not!
    result.map do |tuple| 
      {
        reader_id: tuple["reader_id"], # can this stay as a numeric String?
        name: tuple["name"], # String
        pages_read_today: transform_nil_values_to_zero(tuple["pages_read_today"]), # numeric String?
        pages_read_yesterday: transform_nil_values_to_zero(tuple["pages_read_yesterday"]), # numeric String?
        pages_read_seven_days: transform_nil_values_to_zero(tuple["pages_read_seven_days"]), # numeric String?
        pages_read_ever: transform_nil_values_to_zero(tuple["pages_read_ever"]), # numeric String?
      }
    end
  end

  # add helper method to abstract code that transforms result object into application data object

  # main SQL querying methods
  
  def fetch_all_data
    sql = <<~SQL
    SELECT
      id AS reader_id,
      name,
      (SELECT SUM(pages_read) FROM reading_sessions WHERE session_date = 'today'   AND reader_id = readers.id) AS pages_read_today,
      (SELECT SUM(pages_read) FROM reading_sessions WHERE session_date =   'yesterday' AND reader_id = readers.id) AS pages_read_yesterday,
      (SELECT SUM(pages_read) FROM reading_sessions WHERE session_date BETWEEN   (CURRENT_DATE - 7) AND CURRENT_DATE AND reader_id = readers.id) AS   pages_read_seven_days,
      (SELECT SUM(pages_read) FROM reading_sessions WHERE reader_id = readers.id)   AS pages_read_ever
    FROM readers
    ORDER BY id;
    SQL
  
    # connect to database and get PG::Result object
    result = query(sql)
    
    # transform PG::Result object to common data structure for the app
    transform_result_object_to_data_structure(result)
  end
  
  def fetch_reader_data(reader_id)
    sql = <<~SQL
    SELECT
      id AS reader_id,
      name,
      (SELECT SUM(pages_read) FROM reading_sessions WHERE session_date = 'today'   AND reader_id = readers.id) AS pages_read_today,
      (SELECT SUM(pages_read) FROM reading_sessions WHERE session_date =   'yesterday' AND reader_id = readers.id) AS pages_read_yesterday,
      (SELECT SUM(pages_read) FROM reading_sessions WHERE session_date BETWEEN   (CURRENT_DATE - 7) AND CURRENT_DATE AND reader_id = readers.id) AS   pages_read_seven_days,
      (SELECT SUM(pages_read) FROM reading_sessions WHERE reader_id = readers.id)   AS pages_read_ever
    FROM readers
    WHERE id = $1
    ORDER BY id;
    SQL
  
    # connect to database and get PG::Result object
    result = query(sql, reader_id)
    
    # transform PG::Result object to common data structure for the app
    transform_result_object_to_data_structure(result)
  end
  
  def log_reading_session(reader_id, pages_read)
    sql = "INSERT INTO reading_sessions (reader_id,pages_read) VALUES($1, $2);"
    query(sql, reader_id, pages_read)
  end
  
  def disconnect
    # :nocov:
    # simplecov:disable line
    @db.close 
    # simplecov:enable line
    # :nocov:
  end

end
