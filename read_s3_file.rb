# frozen_string_literal: true

require 'dotenv/load'
require 'aws-sdk-s3'
require 'json'
require 'mysql2'
require 'byebug'
require 'active_record'
require_relative 'services/base_service'
require_relative 'services/data_base_service'
require_relative 'services/matching_product_parse_service'
require_relative 'services/competitive_price_parse_service'
require_relative 'services/lowest_price_listing_parse_service'

# Class to run all services
class ReadS3File
  def initialize
    @entries = []
    @data_array = []
    @file_progress = []
    Aws.config[:s3] = {
      region: 'us-west-1',
      credentials: Aws::Credentials.new(ENV['AWS_ACCESS_KEY_ID_BUCKET'], ENV['AWS_SECRET_ACCESS_KEY_BUCKET']),
      retry_limit: 0
    }
    @s3 = Aws::S3::Client.new(region: 'us-west-1')
  end

  def read_file
    # key = ENV["KEY"]
    key = '44341463.json'
    puts "Key-------------------------------#{key}"
    resp = @s3.get_object(bucket: ENV['AWS_INPUT_BUCKET_NAME'], key: key)
    @entries = JSON.parse(resp.body.read)
    process_entries(@entries)
    return if @entries.blank?

    puts 'File Read!!!!!!!!!!!!'
    puts "-------------------------Fetch all user's client information-------------------------------------------"
    @users = fetch_all_users_clients
    start_time = Time.now
    MatchingProductParseService.new(@entries, @users).start
    end_time = Time.now
    puts "MatchingProductParseService StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    start_time = Time.now
    @file_progress = CompetitivePriceParseService.new(@entries, @users).start
    end_time = Time.now
    puts "CompetitivePriceParseService StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    start_time = Time.now
    @result_array = LowestPriceListingParseService.new(@entries, @users).start
    end_time = Time.now
    puts "LowestPriceListingParseService StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    # start_time = Time.now
    # @file_progress = FeeEstimateParseService.new(@file_progress, @entries, @users).start
    # end_time = Time.now
    # puts "FeeEstimateParseService StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    # start_time = Time.now
    # @file_progress = GetCategoryParseService.new(@file_progress, @entries, @users).start
    # end_time = Time.now
    # puts "GetCategoryParseService StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    # start_time = Time.now
    # @file_progress = JungleScoutEstSale.new(@file_progress, @entries).start
    # end_time = Time.now
    # puts "JungleScoutEstSale StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    # start_time = Time.now
    # @file_progress = AmazonOffersDetail.new(@file_progress, @entries).start
    # end_time = Time.now
    # puts "AmazonOffersDetail StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    # start_time = Time.now
    # @file_progress = PrepFeeEstimateService.new(@file_progress, @entries, @users).start
    # end_time = Time.now
    # puts "PrepFeeEstimateService StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
    # start_time = Time.now
    # FinalizeFileUploadsService.new(@file_progress, @entries).start
    # end_time = Time.now
    # puts "FinalizeFileUploadsService StartTime: #{start_time}, EndTime: #{end_time}, Duration: #{((end_time - start_time) / 60).round(2)} mins"
  end

  def fetch_all_users_clients
    db = DataBaseService.new(
      ENV['DB_USERNAME'],
      ENV['DB_PASSWORD'],
      'fba_support_development_collation',
      ENV['DB_HOST']
    )
    db.execute_sql(
      'SELECT `users`.id as user_id, `users`.seller_id as merchant_id, `users`.mws_market_place_id as
      mws_market_place_id, `users`.mws_access_token as auth_token FROM `users` WHERE `users`.`mws_key_valid` = 1'
    )
  end

  def process_entries(entries)
    puts "Total Entries--------------------#{@entries.size}"
    entries.each do |entry|
      entry['status'] = change_entry_status(entry)
      entry['product_id_value'].rjust(12, '0') if entry['product_id_type'] == 'UPC'
    end
    puts "Total Entries Without Error--------------------#{@entries.reject { |entry| entry['status'] == 'error' }.size}"
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
