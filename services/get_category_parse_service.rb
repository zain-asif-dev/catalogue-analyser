# frozen_string_literal: true

require 'dotenv/load'
require 'peddler'
require 'json'
require 'active_support'
require_relative 'base_service'
require_relative '../modules/services_helper_methods'
require_relative '../modules/mws_request_helper_methods'

# GetCategoryParseService
class GetCategoryParseService < BaseService
  include ServicesHelperMethods
  include MWSRequestHelperMethods
  def initialize(entries, users)
    super()
    initialize_common(entries, THREAD_COUNT, users)
  end

  def send_fetch_and_process_request(user, retries, current_entry)
    category_data = get_data(user, current_entry[:asin])
    @result_array.find { |entry| entry[:asin] == category_data[:asin] }.merge!(category_data) unless category_data.nil?
  rescue StandardError => e
    exception_printer(e)
    retries += 1
    retry if retries <= 3
  end

  def get_data(user, asin, retries = 0)
    fetch_categories_data(user, asin)
  rescue StandardError => e
    retries += 1
    exception_printer(e)
    @user = available_user
    retry if e.message.include?('throttled') || e.message.include?('throttling')
    retry if retries <= 3
  end

  def fetch_categories_data(user, asin)
    @user = user
    client = set_client
    categories = client.get_product_categories_for_asin(user['mws_market_place_id'], asin)
    map_category(asin, check_response(categories))
  end

  def map_category(asin, categories)
    return if categories.blank?

    return map_category_error(asin, categories) if categories['Error'].present?

    categories = [categories['Self']].flatten
    category = categories.first
    category_by_asin = {}
    category_by_asin[:browse_path_by_id], category_by_asin[:browse_path_by_name] = construct_ids_and_names(category)
    return if category_by_asin[:browse_path_by_name].blank?

    { asin: asin, outer_category: category_by_asin[:browse_path_by_name].split(' > ')[0] }
  end

  def map_category_error(asin, categories)
    { asin: asin, status: "error : FetchCompetitivePricingDataService : #{categories.dig('Error', 'Message')}" }
  end

  def product_category_name(product_category)
    product_category['ProductCategoryName']
  end

  def product_category_id(product_category)
    product_category['ProductCategoryId']
  end

  def parent_category(category)
    category['Parent']
  end

  def construct_ids_and_names(node_object, parents_name_array = [], parents_id_array = [])
    unless product_category_name(node_object) == 'Categories'
      parents_id_array.unshift(product_category_id(node_object))
      parents_name_array.unshift(product_category_name(node_object))
    end
    if parent_category(node_object).present?
      return construct_ids_and_names(parent_category(node_object), parents_name_array, parents_id_array)
    end

    [parents_id_array.join(' > '), parents_name_array.join(' > ')]
  end

  def remaining_data
    @search_key_semaphore.synchronize do
      puts "Remaining: GetCategoryParseService #{@_cached_records.count}"
      vendor_asin = @_cached_records.shift
      vendor_asin.present? ? vendor_asin : false
    end
  end
end
