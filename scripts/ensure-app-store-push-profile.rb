# frozen_string_literal: true

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'uri'

API_BASE = 'https://api.appstoreconnect.apple.com/v1'

def base64url(value)
  Base64.urlsafe_encode64(value).delete('=')
end

def app_store_connect_token
  key = OpenSSL::PKey::EC.new(File.read(ENV.fetch('ASC_KEY_P8_PATH')))
  header = base64url(JSON.generate({ alg: 'ES256', kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT' }))
  payload = base64url(JSON.generate({
    iss: ENV.fetch('ASC_ISSUER_ID'),
    exp: Time.now.to_i + 20 * 60,
    aud: 'appstoreconnect-v1'
  }))
  signing_input = "#{header}.#{payload}"
  signature_der = key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(signing_input))
  signature_asn1 = OpenSSL::ASN1.decode(signature_der)
  raw_signature = signature_asn1.value.map do |integer|
    integer.value.to_i.to_s(16).rjust(64, '0')
  end.join
  "#{signing_input}.#{base64url([raw_signature].pack('H*'))}"
end

def request_json(method, path, token, query: nil, body: nil)
  uri = URI("#{API_BASE}#{path}")
  uri.query = URI.encode_www_form(query) if query
  request = case method
            when :get then Net::HTTP::Get.new(uri)
            when :post then Net::HTTP::Post.new(uri)
            else raise "Unsupported request method: #{method}"
            end
  request['Authorization'] = "Bearer #{token}"
  if body
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(body)
  end
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
  return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

  details = begin
    JSON.parse(response.body).fetch('errors', []).map do |error|
      [error['code'], error['title'], error['detail']].compact.join(': ')
    end.join(' | ')
  rescue JSON::ParserError, KeyError
    response.message
  end
  abort "App Store Connect API #{method.to_s.upcase} #{path} failed: HTTP #{response.code} #{details}"
end

def exact_resource(response, attribute, value)
  response.fetch('data').find { |entry| entry.dig('attributes', attribute) == value }
end

token = app_store_connect_token
bundle_identifier = ENV.fetch('BUNDLE_IDENTIFIER')
profile_name = ENV.fetch('PROFILE_NAME')
source_profile_name = ENV.fetch('SOURCE_PROFILE_NAME')
profile_path = ENV.fetch('PROFILE_PATH')

bundle_ids = request_json(
  :get,
  '/bundleIds',
  token,
  query: {
    'filter[identifier]' => bundle_identifier,
    'fields[bundleIds]' => 'identifier,name',
    'limit' => '2'
  }
)
bundle_id = exact_resource(bundle_ids, 'identifier', bundle_identifier)
abort "Bundle ID not found: #{bundle_identifier}" unless bundle_id

capabilities = request_json(
  :get,
  "/bundleIds/#{bundle_id.fetch('id')}/bundleIdCapabilities",
  token,
  query: { 'limit' => '200' }
)
push_enabled = capabilities.fetch('data').any? do |capability|
  capability.dig('attributes', 'capabilityType') == 'PUSH_NOTIFICATIONS'
end

unless push_enabled
  request_json(
    :post,
    '/bundleIdCapabilities',
    token,
    body: {
      data: {
        type: 'bundleIdCapabilities',
        attributes: { capabilityType: 'PUSH_NOTIFICATIONS' },
        relationships: {
          bundleId: { data: { type: 'bundleIds', id: bundle_id.fetch('id') } }
        }
      }
    }
  )
  puts "Enabled Push Notifications for #{bundle_identifier}."
end

profiles = request_json(
  :get,
  '/profiles',
  token,
  query: {
    'filter[name]' => profile_name,
    'fields[profiles]' => 'name,profileContent,profileState,profileType,uuid',
    'limit' => '10'
  }
)
profile = exact_resource(profiles, 'name', profile_name)

unless profile
  source_profiles = request_json(
    :get,
    '/profiles',
    token,
    query: {
      'filter[name]' => source_profile_name,
      'fields[profiles]' => 'name,profileState,profileType,uuid',
      'limit' => '10'
    }
  )
  source_profile = exact_resource(source_profiles, 'name', source_profile_name)
  abort "Source profile not found: #{source_profile_name}" unless source_profile
  abort "Source profile is not active: #{source_profile_name}" unless source_profile.dig('attributes', 'profileState') == 'ACTIVE'

  certificates = request_json(
    :get,
    "/profiles/#{source_profile.fetch('id')}/relationships/certificates",
    token,
    query: { 'limit' => '50' }
  ).fetch('data')
  abort "Source profile has no signing certificate: #{source_profile_name}" if certificates.empty?

  created = request_json(
    :post,
    '/profiles',
    token,
    body: {
      data: {
        type: 'profiles',
        attributes: { name: profile_name, profileType: 'IOS_APP_STORE' },
        relationships: {
          bundleId: { data: { type: 'bundleIds', id: bundle_id.fetch('id') } },
          certificates: { data: certificates }
        }
      }
    }
  )
  profile = created.fetch('data')
  puts "Created provisioning profile: #{profile_name}."
end

attributes = profile.fetch('attributes')
abort "Provisioning profile is not active: #{profile_name}" unless attributes.fetch('profileState') == 'ACTIVE'
File.binwrite(profile_path, Base64.decode64(attributes.fetch('profileContent')))
puts "Fetched profile: #{attributes.fetch('name')} (#{attributes.fetch('uuid')}, #{attributes.fetch('profileState')})"
