# frozen_string_literal: true

require 'dotenv/load'
require 'json'
require 'peddler'
require_relative '../../modules/fetch_services_helper_methods'

# Class to fetch and process data
class FetchLowestPriceListingService
  include FetchServicesHelperMethods
  def initialize(user, users, current_entries)
    initialize_common(user, users)
    @list = current_entries.map { |entry| entry[:asin] }
  end

  def parse_data(pricing_data_set)
    pricing_data_set = pricing_data_set.dig('responses')
    return if pricing_data_set.nil?
    price_data = []
    pricing_data_set.each do |pricing_data|
      pricing_data = pricing_data.dig('body', 'payload')
      asin = pricing_data.dig('ASIN')
      lowest_price_listing_error(pricing_data) if pricing_data['Error'].present?
      next if pricing_data['Summary'].nil? || pricing_data.dig('Summary', 'LowestPrices').nil?

      lowest_offer_listing = pricing_data.dig('Offers')
      amazon_offers = fetch_amazon_offers(lowest_offer_listing)
      merchant_offers = fetch_merchant_offers(lowest_offer_listing)
      lowest_prices = pricing_data.dig('Summary', 'LowestPrices')
      price_data << generate_price_data_hash(asin, lowest_prices, amazon_offers, merchant_offers)
    end
    price_data
  end

  def lowest_price_listing_error(pricing_data)
    {
      asin: pricing_data['ASIN'],
      status: "error : FetchLowestPriceListingService : #{product_data.dig('errors')}"
    }
  end

  def generate_price_data_hash(asin, lowest_prices, amazon_offers, merchant_offers)
    lowestfbaoffer_price = 0
    lowestfbmoffer_price = 0
    lowestfbaoffer = lowest_prices.select{ |hash| hash.dig('fulfillmentChannel') == 'Amazon' }
    lowestfbaoffer_price = lowestfbaoffer[0].dig('ListingPrice', 'Amount') || 0 if lowestfbaoffer.present?
    lowestfbmoffer = lowest_prices.select{ |hash| hash.dig('fulfillmentChannel') == 'Merchant' }
    lowestfbmoffer_price = lowestfbmoffer[0].dig('ListingPrice', 'Amount') || 0 if lowestfbmoffer.present?
    {
      asin: asin,
      totaloffers: amazon_offers.count + merchant_offers.count,
      fbaoffers: amazon_offers.count,
      fbmoffers: merchant_offers.count,
      lowestfbaoffer: lowestfbaoffer_price,
      lowestfbmoffer: lowestfbmoffer_price
    }
  end

  def fetch_merchant_offers(lowest_offer_listing)
    merchant_offers = lowest_offer_listing.select { |item| item['IsFeaturedMerchant'] }
                                          .sort_by { |item| item.dig('ListingPrice', 'Amount').to_f }
    merchant_offers.blank? ? [{}] : merchant_offers
  end

  def fetch_amazon_offers(lowest_offer_listing)
    amazon_offers = lowest_offer_listing.select { |item| item['IsFulfilledByAmazon'] }
                                        .sort_by { |item| item.dig('ListingPrice', 'Amount').to_f }
    amazon_offers.blank? ? [{}] : amazon_offers
  end

  def generate_lowest_price_listing_params(list_items)
    requests = []
    list_items.each do |asin|
      requests << { 'uri': "/products/pricing/v0/items/#{asin}/offers",
                    'method': 'GET',
                    'MarketplaceId': 'ATVPDKIKX0DER',
                    'ItemCondition': 'New' }
    end
    { 'requests': requests }
  end

  def fetch_data(response_arr, list_item)
    response = JSON.parse(lowest_price_listing(generate_lowest_price_listing_params(list_item)).read_body)
    check_response(response, response_arr)
  end
end
