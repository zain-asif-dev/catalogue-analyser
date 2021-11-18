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
    price_data = []
    [pricing_data_set].each do |pricing_data|
      asin = pricing_data['ASIN']
      lowest_price_listing_error(pricing_data) if pricing_data['Error'].present?
      next if pricing_data['Product'].nil? || pricing_data['Product']['LowestOfferListings'].nil?

      lowest_offer_listing = [pricing_data.dig('Product', 'LowestOfferListings', 'LowestOfferListing')].flatten
      amazon_offers = fetch_amazon_offers(lowest_offer_listing)
      merchant_offers = fetch_merchant_offers(lowest_offer_listing)
      price_data << generate_price_data_hash(asin, amazon_offers, merchant_offers)
    end
    price_data
  end

  def lowest_price_listing_error(pricing_data)
    {
      asin: pricing_data['ASIN'],
      status: "error : FetchLowestPriceListingService : #{product_data.dig('Error', 'Message')}"
    }
  end

  def generate_price_data_hash(asin, amazon_offers, merchant_offers)
    lowestfbaoffer = amazon_offers.first.dig('Price', 'ListingPrice', 'Amount') || 0
    lowestfbmoffer = merchant_offers.first.dig('Price', 'ListingPrice', 'Amount') || 0
    {
      asin: asin,
      totaloffers: amazon_offers.count + merchant_offers.count,
      fbaoffers: amazon_offers.count,
      fbmoffers: merchant_offers.count,
      lowestfbaoffer: lowestfbaoffer,
      lowestfbmoffer: lowestfbmoffer
    }
  end

  def fetch_merchant_offers(lowest_offer_listing)
    merchant_offers = lowest_offer_listing.select { |item| item.dig('Qualifiers', 'FulfillmentChannel') == 'Merchant' }
                                          .sort_by { |item| item.dig('Price', 'ListingPrice', 'Amount').to_f }
    merchant_offers.blank? ? [{}] : merchant_offers
  end

  def fetch_amazon_offers(lowest_offer_listing)
    amazon_offers = lowest_offer_listing.reject { |item| item.dig('Qualifiers', 'FulfillmentChannel') == 'Merchant' }
                                        .sort_by { |item| item.dig('Price', 'ListingPrice', 'Amount').to_f }
    amazon_offers.blank? ? [{}] : amazon_offers
  end

  def fetch_data(response_arr, list_item)
    response = @client.get_lowest_offer_listings_for_asin(ENV['MARKETPLACE_ID'], list_item)
    check_response(response, response_arr)
  end
end
