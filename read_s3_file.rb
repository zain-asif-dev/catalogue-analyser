# frozen_string_literal: true

require 'dotenv/load'
require 'aws-sdk-s3'
require 'aws-sdk-signer'
require 'aws-sdk-sts'
require 'aws-sdk-sqs'
require 'httparty'
require 'json'
require 'net/http'
# require 'byebug' # Enable for debugging

require_relative 'services/base_service'
require_relative 'services/data_base_service'
require_relative 'services/matching_product_parse_service'
require_relative 'services/competitive_price_parse_service'
require_relative 'services/fee_estimate_parse_service'
require_relative 'services/lowest_price_listing_parse_service'
require_relative 'services/get_category_parse_service'
require_relative 'services/jungle_scout_est_sale'
require_relative 'services/amazon_offers_detail'
require_relative 'services/prep_fee_estimate_service'
require_relative 'services/generate_file_output_service'

# Class to run all services
class ReadS3File
  def initialize
    @entries = []
    @data_array = []
    Aws.config[:s3] = {
      region: 'us-west-1',
      credentials: Aws::Credentials.new(ENV['AWS_ACCESS_KEY_ID_BUCKET'], ENV['AWS_SECRET_ACCESS_KEY_BUCKET']),
      retry_limit: 0
    }
    @s3 = Aws::S3::Client.new(region: 'us-west-1')
    @users = fetch_all_users_clients
  end

  def read_file
    key = ENV['KEY']
    # key = '85164169.json'
    puts "Key-------------------------------#{key}"
    resp = @s3.get_object(bucket: ENV['AWS_INPUT_BUCKET_NAME'], key: key)
    @entries = JSON.parse(resp.body.read)
    @entries = @entries.first(20) unless ENV['BASE_URL'].include?('sales.support')
    process_entries(@entries)
    return update_file_status(0, '-1', nil) if @entries.blank?

    start_t = Time.now
    puts 'File Read!!!!!!!!!!!!'
    puts "-------------------------Fetch all user's client information-------------------------------------------"
    @users = fetch_all_users_clients
    start_time = Time.now
    @data_array = MatchingProductParseService.new(@entries, @users).start
    end_time = Time.now
    update_file_status(12.5)
    puts "MatchingProductParseService StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    start_time = Time.now
    CompetitivePriceParseService.new(@data_array, @users).start
    end_time = Time.now
    update_file_status(25)
    puts "CompetitivePriceParseService StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    start_time = Time.now
    LowestPriceListingParseService.new(@data_array, @users).start
    end_time = Time.now
    update_file_status(37.5)
    puts "LowestPriceListingParseService StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    start_time = Time.now
    FeeEstimateParseService.new(@data_array, @users).start
    end_time = Time.now
    update_file_status(50)
    puts "FeeEstimateParseService StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    # start_time = Time.now
    # GetCategoryParseService.new(@data_array, @users).start
    # end_time = Time.now
    # update_file_status(62.5)
    # puts "GetCategoryParseService StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    # start_time = Time.now
    # JungleScoutEstSale.new(@data_array).start
    # end_time = Time.now
    # puts "JungleScoutEstSale StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    start_time = Time.now
    AmazonOffersDetail.new(@data_array).start
    end_time = Time.now
    update_file_status(75)
    puts "AmazonOffersDetail StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    start_time = Time.now
    PrepFeeEstimateService.new(@data_array, @users).start
    end_time = Time.now
    update_file_status(87.5)
    puts "PrepFeeEstimateService StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    start_time = Time.now
    file_name, file_url = GenerateFileOutputService.new(@data_array.reject { |e| e[:status]&.include?('error') }).generate_catalog_output
    end_time = Time.now
    puts "GenerateFileOutputService StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    end_t = Time.now
    puts "Total  StartTime: #{start_t}, EndTime: #{end_t}, Duration: #{((end_t - start_t) / 60).round(2)} mins"
    Aws::S3::Resource.new.bucket(ENV['AWS_OUTPUT_BUCKET_NAME']).put_object({ key: key, body: @data_array.to_json, acl: 'public-read'})
    # puts "-----------------------------#{s3_object.public_url}"
    update_file_status(100, file_name, file_url)
  rescue StandardError => e
    puts e.message
    puts e.backtrace.join('\n')
    update_file_status(0, '-1', nil)
  end

  def update_file_status(progress, file_name = nil, file_url = nil)
    http, request = generate_request
    body = { 'progress': progress, 'output_file_name': file_name, 'output_file_url': file_url }
    request.body = body.to_json
    rescue_exceptions do
      response = http.request(request)
      record = JSON.parse(response.body)
      record['message']
    end
  end

  def generate_request
    uri = URI.parse("#{ENV['BASE_URL']}/api/v3/amazon_files/#{ENV['FILE_ID']}/update_file_status")
    request = Net::HTTP::Put.new(uri.request_uri)
    request['Content-Type'] = 'application/json'
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if ENV['BASE_URL'].include?('sales.support')
    [http, request]
  end

  def rescue_exceptions
    yield
  rescue StandardError => e
    puts "Error: #{e}"
    false
  end

  def fetch_all_users_clients
    response = @s3.get_object(bucket: ENV['AWS_AMAZON_CREDENTIALS_BUCKET'], key: 'amazon_user_credentials.json')
    @users = JSON.parse(response.body.read)
  end

  def process_entries(entries)
    puts "Total Entries--------------------#{@entries.size}"
    entries.each do |entry|
      entry['status'] = change_entry_status(entry)
      entry['product_id_value'].rjust(12, '0') if entry['product_id_type'] == 'UPC'
    end
    puts "Total Entries Without Error-------------------#{@entries.reject { |entry| entry['status'] == 'error' }&.size}"
  end

  def change_entry_status(entry)
    if entry['isInvalid']
      'error'
    elsif entry['product_id_type'] == 'ASIN' && entry['product_id_value'].length < 10
      'error'
    else
      'processing'
    end
  end
end

ReadS3File.new.read_file
