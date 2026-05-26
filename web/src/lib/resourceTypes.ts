/**
 * Map an Azure `Microsoft.Foo/bars` resource type to:
 *  - a short human label (e.g. "Web App")
 *  - a category color (used as the fallback icon background)
 *  - the SVG filename under `/icons/` (without `.svg`)
 *
 * Icons under `/icons/` are GENERIC open-source placeholders. To get the real
 * Azure architecture icons run `npm run fetch-icons` (acknowledges Microsoft's
 * license terms locally; nothing is committed to the repo).
 */
export interface ResourceTypeMeta {
  label: string;
  category:
    | 'compute'
    | 'storage'
    | 'network'
    | 'database'
    | 'security'
    | 'integration'
    | 'identity'
    | 'monitoring'
    | 'web'
    | 'ai'
    | 'devops'
    | 'management'
    | 'other';
  icon: string;
}

const CATEGORY_COLORS: Record<ResourceTypeMeta['category'], string> = {
  compute: '#7FBA00',
  storage: '#0072C6',
  network: '#0072C6',
  database: '#3999C6',
  security: '#E81123',
  integration: '#FFB900',
  identity: '#F25022',
  monitoring: '#737373',
  web: '#00BCF2',
  ai: '#8661C5',
  devops: '#00A4EF',
  management: '#4B53BC',
  other: '#5C2D91',
};

const MAP: Record<string, ResourceTypeMeta> = {
  // Compute
  'microsoft.compute/virtualmachines': { label: 'Virtual Machine', category: 'compute', icon: 'vm' },
  'microsoft.compute/virtualmachines/extensions': {
    label: 'VM Extension',
    category: 'compute',
    icon: 'vm-extension',
  },
  'microsoft.compute/virtualmachinescalesets': {
    label: 'VM Scale Set',
    category: 'compute',
    icon: 'vmss',
  },
  'microsoft.compute/disks': { label: 'Managed Disk', category: 'compute', icon: 'disk' },
  'microsoft.compute/snapshots': { label: 'Snapshot', category: 'compute', icon: 'disk' },
  'microsoft.containerservice/managedclusters': { label: 'AKS', category: 'compute', icon: 'aks' },
  'microsoft.containerregistry/registries': {
    label: 'Container Registry',
    category: 'compute',
    icon: 'acr',
  },
  // Web
  'microsoft.web/sites': { label: 'App Service', category: 'web', icon: 'app-service' },
  'microsoft.web/serverfarms': { label: 'App Service Plan', category: 'web', icon: 'app-service-plan' },
  'microsoft.web/staticsites': { label: 'Static Web App', category: 'web', icon: 'static-web-app' },
  // Storage
  'microsoft.storage/storageaccounts': { label: 'Storage Account', category: 'storage', icon: 'storage' },
  // Network
  'microsoft.network/virtualnetworks': { label: 'Virtual Network', category: 'network', icon: 'vnet' },
  'microsoft.network/virtualnetworks/subnets': { label: 'Subnet', category: 'network', icon: 'subnet' },
  'microsoft.network/networkinterfaces': { label: 'NIC', category: 'network', icon: 'nic' },
  'microsoft.network/networksecuritygroups': { label: 'NSG', category: 'security', icon: 'nsg' },
  'microsoft.network/publicipaddresses': { label: 'Public IP', category: 'network', icon: 'public-ip' },
  'microsoft.network/routetables': { label: 'Route Table', category: 'network', icon: 'route-table' },
  'microsoft.network/loadbalancers': { label: 'Load Balancer', category: 'network', icon: 'lb' },
  'microsoft.network/applicationgateways': {
    label: 'App Gateway',
    category: 'network',
    icon: 'app-gateway',
  },
  'microsoft.network/privateendpoints': {
    label: 'Private Endpoint',
    category: 'network',
    icon: 'private-endpoint',
  },
  'microsoft.network/frontdoors': { label: 'Front Door', category: 'network', icon: 'front-door' },
  // Database
  'microsoft.sql/servers': { label: 'SQL Server', category: 'database', icon: 'sql' },
  'microsoft.sql/servers/databases': { label: 'SQL DB', category: 'database', icon: 'sql' },
  'microsoft.dbforpostgresql/flexibleservers': {
    label: 'Postgres Flex',
    category: 'database',
    icon: 'postgres',
  },
  'microsoft.documentdb/databaseaccounts': { label: 'Cosmos DB', category: 'database', icon: 'cosmos' },
  'microsoft.cache/redis': { label: 'Redis Cache', category: 'database', icon: 'redis' },
  // Security
  'microsoft.keyvault/vaults': { label: 'Key Vault', category: 'security', icon: 'key-vault' },
  // Identity
  'microsoft.managedidentity/userassignedidentities': {
    label: 'Managed Identity',
    category: 'identity',
    icon: 'managed-identity',
  },
  // Monitoring
  'microsoft.insights/components': {
    label: 'App Insights',
    category: 'monitoring',
    icon: 'app-insights',
  },
  'microsoft.operationalinsights/workspaces': {
    label: 'Log Analytics',
    category: 'monitoring',
    icon: 'log-analytics',
  },
  // Integration
  'microsoft.eventgrid/systemtopics': {
    label: 'Event Grid Topic',
    category: 'integration',
    icon: 'event-grid',
  },
  'microsoft.eventhub/namespaces': { label: 'Event Hub', category: 'integration', icon: 'event-hub' },
  'microsoft.servicebus/namespaces': { label: 'Service Bus', category: 'integration', icon: 'service-bus' },
  'microsoft.apimanagement/service': { label: 'APIM', category: 'integration', icon: 'apim' },
};

const FALLBACK: ResourceTypeMeta = { label: 'Resource', category: 'other', icon: '_default' };

export function metaForType(type: string): ResourceTypeMeta {
  return MAP[type.toLowerCase()] ?? FALLBACK;
}

export function colorForCategory(cat: ResourceTypeMeta['category']): string {
  return CATEGORY_COLORS[cat];
}
