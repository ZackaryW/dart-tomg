// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_plans.dart';

// **************************************************************************
// TomgGenerator
// **************************************************************************

const Map<PlanTier, ServicePlan> $ServicePlan = <PlanTier, ServicePlan>{
  PlanTier.starter: ServicePlan(
    tier: PlanTier.starter,
    limits: ServicePlanLimits(projects: 3, storageGb: 10.0),
    locations: const <ServicePlanLocationsItem>[
      ServicePlanLocationsItem(code: "us-east", primary: true),
      ServicePlanLocationsItem(code: "eu-west", primary: false),
    ],
    regions: const <String>["us-east", "eu-west"],
    transports: const <Transport>[Transport.https],
  ),
  PlanTier.enterprise: ServicePlan(
    tier: PlanTier.enterprise,
    description: "Multi-region plan",
    limits: ServicePlanLimits(projects: 100, storageGb: 1000.0),
    locations: const <ServicePlanLocationsItem>[
      ServicePlanLocationsItem(
        code: "us-east",
        note: "Primary production region",
        primary: true,
      ),
      ServicePlanLocationsItem(code: "eu-west", primary: false),
    ],
    regions: const <String>["us-east", "eu-west"],
    transports: const <Transport>[Transport.https, Transport.grpc],
  ),
};
