// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_endpoints.dart';

// **************************************************************************
// TomgGenerator
// **************************************************************************

const Map<String, ApiEndpoint> $ApiEndpoint = <String, ApiEndpoint>{
  "us-east": ApiEndpoint(
    id: "us-east",
    environment: "production",
    name: "US East",
    url: "Mkjll1xXlzukCWuDPoCjBDtP5clKFdl5tRVngyic4w==",
  ),
  "eu-west": ApiEndpoint(
    id: "eu-west",
    enabled: false,
    environment: "production",
    name: "EU West",
    url: "Mkjll1xXlzukCWuDLoajFj9P5clKFdl5tRVngyic4w==",
  ),
  "staging": ApiEndpoint(
    id: "staging",
    environment: "staging",
    name: "Staging",
    url: "Mkjll1xXlzu2DWPKIp3pTz9E8IpfAd06phZv",
    visible: false,
  ),
};

/// Decoded view of [ApiEndpoint]'s `@Obfus` fields.
class ApiEndpointDeobf {
  const ApiEndpointDeobf(this._o);

  final ApiEndpoint _o;

  String get id => _o.id;
  bool get enabled => _o.enabled;
  String get environment => _o.environment;
  String get name => _o.name;
  String get url => _o.url.deobf;
  bool get visible => _o.visible;
}
