import 'package:dart_tomg_example/generated/service_plans.dart';
import 'package:test/test.dart';

void main() {
  test('uses an enum as the registry key', () {
    expect(servicePlanRegistry.keys, containsAll(PlanTier.values));
  });

  test('generates typed scalar and enum lists in source order', () {
    final starter = servicePlanRegistry[PlanTier.starter]!;
    expect(starter.regions, const <String>['us-east', 'eu-west']);
    expect(starter.transports, const <Transport>[Transport.https]);

    final enterprise = servicePlanRegistry[PlanTier.enterprise]!;
    expect(enterprise.transports, const <Transport>[
      Transport.https,
      Transport.grpc,
    ]);
  });

  test('keeps an omitted optional nullable field at its default', () {
    expect(servicePlanRegistry[PlanTier.starter]!.description, isNull);
    expect(
      servicePlanRegistry[PlanTier.enterprise]!.description,
      'Multi-region plan',
    );
  });

  test('uses automatically inferred nested objects and model lists', () {
    final starter = servicePlanRegistry[PlanTier.starter]!;
    expect(starter.limits.projects, 3);
    expect(starter.limits.storageGb, 10.0);
    expect(starter.locations, hasLength(2));
    expect(starter.locations.first.code, 'us-east');
    expect(starter.locations.first.primary, isTrue);
    expect(starter.locations.first.note, isNull);

    final enterprise = servicePlanRegistry[PlanTier.enterprise]!;
    expect(enterprise.limits.projects, 100);
    expect(enterprise.locations.first.note, 'Primary production region');
  });
}
