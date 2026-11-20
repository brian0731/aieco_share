import { fail } from './database'

export const hongKongDistrictIds = [
  'hk-central-western',
  'hk-eastern',
  'hk-southern',
  'hk-wan-chai',
  'hk-kowloon-city',
  'hk-yau-tsim-mong',
  'hk-sham-shui-po',
  'hk-wong-tai-sin',
  'hk-kwun-tong',
  'hk-tai-po',
  'hk-yuen-long',
  'hk-tuen-mun',
  'hk-north',
  'hk-sai-kung',
  'hk-sha-tin',
  'hk-tsuen-wan',
  'hk-kwai-tsing',
  'hk-islands',
] as const

export function requiredDistrict(value: unknown) {
  if (value == null || value === '') fail(400, 'district_required')
  const district = hongKongDistrictIds.find(id => id === value)
  if (!district) fail(400, 'invalid_district')
  return district
}
