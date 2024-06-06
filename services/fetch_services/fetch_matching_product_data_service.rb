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
    return [{ data: product_data, error: 'Null data hash!' }] if product_data.nil?

    asins_data = []
    return asins_data if product_data_error(product_data, asins_data)

    asins_data << generate_asins_data_hash(product_data, product_data_id(product_data))
    asins_data
  end

  def product_data_error(product_data, asins_data)
    if product_data['Error'].present?
      entry = current_entry(product_data_id(product_data))
      asins_data << entry_hash_required_data(entry).merge(
        { status: "error : FetchMatchingProductDataService : #{product_data&.dig('Error', 'Message')}" }
      )
      true
    else
      false
    end
  end

  def generate_asins_data_hash(asin_data, product_data_id)
    upc = nil
    ean = nil
    isbn = nil
    asin_data.dig('identifiers').each do |marketpalce_data|
      next unless marketpalce_data['marketplaceId'] == 'ATVPDKIKX0DER'

      marketpalce_data.dig('identifiers').each do |hash|
        case hash['identifierType']
        when 'UPC'
          upc = hash['identifier']
        when 'EAN'
          ean = hash['identifier']
        when 'ISBN'
          isbn = hash['identifier']
        end
      end
    end
    add_asin_hash_to_asins_array(asin_data, upc, ean, isbn).merge(entry_hash_required_data(current_entry(product_data_id)))
  end

  def entry_hash_required_data(entry)
    return { error: 'Entry data null!' } if entry.nil?

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

  def add_asin_hash_to_asins_array(asin_data, upc, ean, isbn)
    package_quantity = asin_data.dig('attributes', 'item_package_quantity', 0, 'value') || 1
    {
      asin: asin_data['asin'],
      packagequantity: package_quantity.to_i > 30_000 ? 30_000 : package_quantity.to_i,
      salesrank: sales_rank(asin_data),
      upc: upc,
      ean: ean,
      isbn: isbn
    }.merge(generating_asin_hash(asin_data))
  end

  def generating_asin_hash(asin_data)
    category = asin_data.dig('salesRanks', 0, 'displayGroupRanks')
    outer_category = category[0].dig('title') if category.present?
    {
      name: asin_data.dig('attributes', 'item_name', 0, 'value'),
      brand: asin_data.dig('attributes', 'brand', 0, 'value').presence,
      product_type: asin_data.dig('productTypes', 0, 'productType'),
      outer_category: outer_category || ''
    }.merge(add_item_dimensions(asin_data.dig('dimensions', 0, 'item')))
     .merge(add_package_dimensions(asin_data.dig('dimensions', 0, 'package')))
     .merge(images_data(asin_data.dig('images', 0, 'images')))
  end

  def add_package_dimensions(asin_data)
    data = map_dimensions(asin_data)
    {
      packageweight: data[:height].round(2),
      packageheight: data[:width].round(2),
      packagelength: data[:length].round(2),
      packagewidth: data[:weight].round(2)
    }
  end

  def add_item_dimensions(asin_data)
    data = map_dimensions(asin_data)
    {
      height: data[:height].round(2),
      width: data[:width].round(2),
      length: data[:length].round(2),
      weight: data[:weight].round(2)
    }
  end

  def map_dimensions(asin_data)
    data = { height: 0,
             width: 0,
             length: 0,
             weight: 0 }
    return data if asin_data.nil?

    asin_data.each do |key, value|
      case key
      when 'height'
        data[:height] = check_units(value)
      when 'width'
        data[:width] = check_units(value)
      when 'length'
        data[:length] = check_units(value)
      when 'weight'
        data[:weight] = convert_weight_to_pounds(value)
      end
    end
    data
  end

  def images_data(images_hash)
    small_image = nil
    medium_image = nil
    large_image = nil
    images_hash.select{|a| a["variant"] == 'MAIN'}.each do |image_hash|
      if image_hash['height'] < 100
        small_image = image_hash.dig('link')
      elsif image_hash['height'] < 1000
        medium_image = image_hash.dig('link')
      else
        large_image = image_hash.dig('link')
      end
    end
    {
      small_image: small_image,
      medium_image: medium_image,
      large_image: large_image
    }
  end

  def sales_rank(asin_data)
    return asin_data.dig('salesRanks', 0, 'displayGroupRanks', 0, 'rank') if asin_data.dig('salesRanks', 0, 'displayGroupRanks').present?

    0
  end

  def product_data_id(product_data)
    product_data.dig('identifiers').each do |marketpalce_data|
      next unless marketpalce_data['marketplaceId'] == 'ATVPDKIKX0DER'

      marketpalce_data.dig('identifiers').each do |hash|
        return hash['identifier'].to_s if hash['identifierType'].upcase == @list_type.upcase
      end
    end
  end

  def check_units(hash)
    return 0 if hash.nil?

    return hash['value'] if hash['unit'].downcase == 'inches'

    return centi_meter_to_inches(hash['value']).round(2) if hash['unit'].downcase == 'centimeters'

    puts '**************************Check required********************************************* '
    puts hash['unit'].downcase
    puts '*************************************************************************************'
  end

  def centi_meter_to_inches(cm)
    (cm * 0.393701).round(2)
  end

  def convert_weight_to_pounds(hash)
    return if hash.nil?

    unit = hash['unit'].upcase

    shipping_weight = hash['value'].to_f

    return unless unit

    return (shipping_weight / 454.to_f).round(2) if ['G', 'GRAM', 'GRAMS'].include?(unit)
    return shipping_weight.round(2) if ['LB', 'LBS', 'POUND', 'POUNDS'].include?(unit)
    return (shipping_weight / 16.to_f).round(2) if ['OZ', 'OUNCE', 'OUNCES'].include?(unit)
    return (shipping_weight / 2.205.to_f).round(2) if ['KG', 'KILOGRAMS'].include?(unit)
    return (shipping_weight / 453_592.37.to_f).round(2) if ['MG', 'MILLIGRAMS'].include?(unit)
  end

  def fetch_data(response_arr, list_item)
    raw_response = catalog_matching_product(list_item)
    parsed_response = JSON.parse(raw_response.read_body)
    response = parsed_response.dig('items')
    while parsed_response.dig('pagination', 'nextToken')
      next_token = parsed_response.dig('pagination', 'nextToken').gsub('=', '')
      parsed_response = JSON.parse(catalog_matching_product(list_item, next_token).read_body)
      response << parsed_response.dig('items')
    end

    check_response(response&.flatten, response_arr)
  end
end
