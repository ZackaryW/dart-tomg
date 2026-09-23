import 'package:dart_tomg_example/generated/api_endpoints.dart';
import 'package:dart_tomg_example/generated/service_plans.dart';

void main() {
  final endpoint = apiEndpointRegistry['us-east']!;
  print('${endpoint.name}: ${endpoint.deobf.url}');

  final plan = servicePlanRegistry[PlanTier.starter]!;
  print('${plan.tier.name}: ${plan.regions.join(', ')}');
}
