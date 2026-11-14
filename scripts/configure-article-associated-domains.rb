# frozen_string_literal: true

require 'base64'
require 'json'
require 'net/http'
require 'open3'
require 'openssl'
require 'tempfile'
require 'uri'

API_BASE = 'https://api.appstoreconnect.apple.com/v1'
BUNDLE_IDENTIFIER = 'com.kou888.myharness'
SOURCE_PROFILE = 'my-harness-app-store-push-v3'
TARGET_PROFILE = 'my-harness-app-store-associated-domains-v4'

def base64url(value)
  Base64.urlsafe_encode64(value).delete('=')
end

def token
  key = OpenSSL::PKey::EC.new(File.read(ENV.fetch('ASC_KEY_P8_PATH')))
  header = base64url(JSON.generate(alg: 'ES256', kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT'))
  payload = base64url(JSON.generate(iss: ENV.fetch('ASC_ISSUER_ID'), exp: Time.now.to_i + 1200, aud: 'appstoreconnect-v1'))
  signing_input = "#{header}.#{payload}"
  signature = OpenSSL::ASN1.decode(key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(signing_input)))
    .value.map { |integer| integer.value.to_i.to_s(16).rjust(64, '0') }.join
  "#{signing_input}.#{base64url([signature].pack('H*'))}"
end

def request_json(method, path, bearer, query: nil, body: nil)
  uri = URI("#{API_BASE}#{path}")
  uri.query = URI.encode_www_form(query) if query
  request = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{bearer}"
  if body
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(body)
  end
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
  return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

  warn "App Store Connect request failed: #{method.to_s.upcase} #{path} HTTP #{response.code}"
  begin
    errors = JSON.parse(response.body).fetch('errors', [])
    codes = errors.filter_map do |error|
      code = error.is_a?(Hash) ? error['code'].to_s : ''
      code if code.match?(/\A[A-Za-z0-9_.-]{1,80}\z/)
    end
    warn "App Store Connect error codes: #{codes.join(', ')}" unless codes.empty?
  rescue JSON::ParserError, TypeError
    # Never print the raw response, authorization header, or private key.
  end
  exit 1
end

def named_profile(name, bearer)
  result = request_json(:get, '/profiles', bearer, query: {
    'filter[name]' => name,
    'fields[profiles]' => 'name,profileContent,profileState,profileType,uuid',
    'limit' => '10'
  })
  result.fetch('data').find { |entry| entry.dig('attributes', 'name') == name }
end

def profile_entitlements(profile)
  content = Base64.decode64(profile.fetch('attributes').fetch('profileContent'))
  Tempfile.create(['article-profile', '.mobileprovision']) do |source|
    source.binmode
    source.write(content)
    source.flush
    xml, error, status = Open3.capture3('/usr/bin/security', 'cms', '-D', '-i', source.path)
    abort "Cannot decode provisioning profile: #{error.lines.first}" unless status.success?
    Tempfile.create(['article-profile', '.plist']) do |plist|
      plist.write(xml)
      plist.flush
      read = lambda do |key|
        output, _error, result = Open3.capture3('/usr/libexec/PlistBuddy', '-c', "Print :#{key}", plist.path)
        result.success? ? output.strip : nil
      end
      groups = []
      index = 0
      while (group = read.call("Entitlements:com.apple.security.application-groups:#{index}"))
        groups << group
        index += 1
      end
      return {
        prefix: read.call('ApplicationIdentifierPrefix:0'),
        team_id: read.call('TeamIdentifier:0'),
        app_identifier: read.call('Entitlements:application-identifier'),
        push: read.call('Entitlements:aps-environment'),
        groups: groups,
        associated_domains: !read.call('Entitlements:com.apple.developer.associated-domains').nil?
      }
    end
  end
end

def verify_profile(profile, associated_domains:)
  abort 'Profile is not active' unless profile.dig('attributes', 'profileState') == 'ACTIVE'
  plist = profile_entitlements(profile)
  prefix = plist.fetch(:prefix)
  team_id = plist.fetch(:team_id)
  abort 'Application identifier prefix is invalid' unless prefix&.match?(/\A[A-Z0-9]{10}\z/)
  abort 'Profile team identifier is invalid' unless team_id&.match?(/\A[A-Z0-9]{10}\z/)
  abort 'Profile application identifier mismatch' unless plist.fetch(:app_identifier) == "#{prefix}.#{BUNDLE_IDENTIFIER}"
  abort 'Push entitlement missing' unless plist.fetch(:push) == 'production'
  abort 'App Group entitlement missing' unless plist.fetch(:groups).include?('group.com.kou888.myharness')
  if associated_domains
    abort 'Associated Domains entitlement missing' unless plist.fetch(:associated_domains)
  end
  prefix
end

mode = ENV.fetch('MODE')
abort 'MODE must be inspect or apply' unless %w[inspect apply].include?(mode)
bearer = token
bundle_ids = request_json(:get, '/bundleIds', bearer, query: {
  'filter[identifier]' => BUNDLE_IDENTIFIER,
  'fields[bundleIds]' => 'identifier,name',
  'limit' => '2'
})
bundle = bundle_ids.fetch('data').find { |entry| entry.dig('attributes', 'identifier') == BUNDLE_IDENTIFIER }
abort 'Existing app bundle ID was not found' unless bundle
bundle_id = bundle.fetch('id')
capabilities = request_json(:get, "/bundleIds/#{bundle_id}/bundleIdCapabilities", bearer).fetch('data')
types = capabilities.map { |item| item.dig('attributes', 'capabilityType') }
abort 'Existing Push Notifications capability missing' unless types.include?('PUSH_NOTIFICATIONS')
source = named_profile(SOURCE_PROFILE, bearer)
abort 'Existing App Store profile was not found' unless source
prefix = verify_profile(source, associated_domains: false)
puts "Application Identifier Prefix: #{prefix}"
puts "Existing App ID Associated Domains: #{types.include?('ASSOCIATED_DOMAINS') ? 'enabled' : 'disabled'}"
puts "Existing app profile: #{SOURCE_PROFILE} (active, Push and App Group present)"

target = named_profile(TARGET_PROFILE, bearer)
if mode == 'inspect'
  if target
    verify_profile(target, associated_domains: true)
    puts "Associated Domains profile: #{TARGET_PROFILE} (active)"
  else
    puts 'Associated Domains profile: absent'
  end
  exit 0
end

unless types.include?('ASSOCIATED_DOMAINS')
  request_json(:post, '/bundleIdCapabilities', bearer, body: {
    data: {
      type: 'bundleIdCapabilities',
      attributes: { capabilityType: 'ASSOCIATED_DOMAINS' },
      relationships: { bundleId: { data: { type: 'bundleIds', id: bundle_id } } }
    }
  })
  puts 'Enabled Associated Domains on the existing app ID.'
end

unless target
  certificates = request_json(:get, "/profiles/#{source.fetch('id')}/relationships/certificates", bearer, query: { 'limit' => '50' }).fetch('data')
  abort 'Existing profile has no distribution certificate' if certificates.empty?
  created = request_json(:post, '/profiles', bearer, body: {
    data: {
      type: 'profiles',
      attributes: { name: TARGET_PROFILE, profileType: 'IOS_APP_STORE' },
      relationships: {
        bundleId: { data: { type: 'bundleIds', id: bundle_id } },
        certificates: { data: certificates }
      }
    }
  })
  target = created.fetch('data')
  puts "Created app distribution profile: #{TARGET_PROFILE}"
end
target = named_profile(TARGET_PROFILE, bearer) unless target.dig('attributes', 'profileContent')
abort 'Created profile was not found' unless target
target_prefix = verify_profile(target, associated_domains: true)
abort 'Profile prefix changed unexpectedly' unless target_prefix == prefix
puts "Verified app profile: #{TARGET_PROFILE} (active, Push, App Group, Associated Domains present)"
