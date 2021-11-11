# frozen_string_literal: true

# A service to connect to database
class DataBaseService
  def initialize(username, password, db_name, host)
    @username = username
    @password = password
    @db_name = db_name
    @host = host
    connect
  end

  def connect
    ActiveRecord::Base.establish_connection(
      adapter: 'mysql2',
      host: @host,
      username: @username,
      password: @password,
      database: @db_name
    )
    puts 'Successfully connected to database'
  rescue StandardError => e
    puts "Error! Couldn't establish connection to database. #{e.message}"
  end

  def get_array_from_execute_query(query_result)
    query_result.each(as: :hash) { |row| row[:field] }
  end

  def execute_sql(sql_query)
    query = ActiveRecord::Base.sanitize_sql(sql_query)
    query_result = ActiveRecord::Base.connection.execute(query)
    get_array_from_execute_query(query_result)
  end
end
