# frozen_string_literal: true

require 'dotenv/load'
require 'json'
require 'peddler'
require_relative '../../modules/fetch_services_helper_methods'

# Class to Fetch Mathing Product Data
class FetchMatchingProductDataService
  include FetchServicesHelperMethods
  def initialize(user, users, current_entries)
    initialize_common(user, users)
    @entries = current_entries
    @list = current_entries.map { |entry| entry['product_id_value'] }
    @list_type = current_entries.first['product_id_type']
  end

  def parse_data(product_data)
    asins_data = []
    return asins_data if product_data_error(product_data, asins_data)

    asins = [product_data['Products']['Product']].flatten
    asins.each do |asin_data|
      generate_asins_data_hash(asins_data, asin_data, product_data['Id'], product_data['IdType'])
    end
    asins_data
  end

  def product_data_error(product_data, asins_data)
    if product_data['Error'].present?
      entry = current_entry(product_data['Id'])
      asins_data << entry_hash_required_data(entry).merge(
        { status: "error : FetchMatchingProductDataService : #{product_data.dig('Error', 'Message')}" }
      )
      true
    else
      false
    end
  end

  def entry_hash_required_data(entry)
    {
      status: entry['status'],
      sku: entry['sku'],
      item_description: entry['item_description'],
      cost_price: entry['cost_price']
    }
  end

  def current_entry(product_data_id)
    @entries.find { |item| item['product_id_value'] == product_data_id }
  end

  def generate_asins_data_hash(asins_data, asin_data, product_data_id, product_data_type)
    case product_data_type
    when 'UPC'
      upc = product_data_id
    when 'EAN'
      ean = product_data_id
    when 'ISBN'
      isbn = product_data_id
    end
    asins_data << add_asin_hash_to_asins_array(asin_data, upc, ean, isbn)
                  .merge(entry_hash_required_data(current_entry(product_data_id)))
  end

  def add_asin_hash_to_asins_array(asin_data, upc, ean, isbn)
    package_quantity = asin_data.dig('AttributeSets', 'ItemAttributes', 'PackageQuantity') || 1
    {
      asin: asin_data.dig('Identifiers', 'MarketplaceASIN', 'ASIN').strip,
      packagequantity: package_quantity.to_i > 30_000 ? 30_000 : package_quantity.to_i,
      salesrank: sales_rank(asin_data),
      upc: upc,
      ean: ean,
      isbn: isbn
    }.merge(generating_asin_hash(asin_data.dig('AttributeSets', 'ItemAttributes')))
  end

  def generating_asin_hash(asin_data)
    {
      name: asin_data['Title'],
      brand: (asin_data['Brand'].presence ||
             asin_data['Label']),
      product_type: asin_data['ProductTypeName'].presence,
      small_image: (asin_data.dig('SmallImage', 'URL') || '')
    }.merge(add_item_dimensions(asin_data['ItemDimensions']))
      .merge(add_package_dimensions(asin_data['PackageDimensions']))
  end

  def add_package_dimensions(asin_data)
    asin_data = {} if asin_data.nil?
    {
      packageweight: asin_data.dig('Weight', '__content__') || 0,
      packageheight: asin_data.dig('Height', '__content__') || 0,
      packagelength: asin_data.dig('Length', '__content__') || 0,
      packagewidth: asin_data.dig('Width', '__content__') || 0
    }
  end

  def add_item_dimensions(asin_data)
    asin_data = {} if asin_data.nil?
    {
      height: asin_data.dig('Height', '__content__') || 0,
      width: asin_data.dig('Width', '__content__') || 0,
      length: asin_data.dig('Length', '__content__') || 0,
      weight: asin_data.dig('Weight', '__content__') || 0
    }
  end

  def sales_rank(asin_data)
    return [asin_data['SalesRankings']['SalesRank']].flatten.first['Rank'] if asin_data['SalesRankings'].present?

    0
  end

  def fetch_data(response_arr, list_item)
    response = @client.get_matching_product_for_id(ENV['MARKETPLACE_ID'], @list_type, list_item)
    check_response(response, response_arr)
  end
end
