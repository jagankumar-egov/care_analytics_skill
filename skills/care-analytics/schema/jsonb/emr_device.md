# emr_device JSONB shapes

Distilled from Pydantic API specs — strong hints, not guarantees; custom serializers can change the stored shape.

## history

- shape unknown — no spec declares this field (check serializers; default is dict)

## meta

- dict, optional — DeviceCreateSpec, DeviceListSpec, DeviceRetrieveSpec, DeviceSpecBase +2

## contact

- list[ContactPoint], optional — DeviceCreateSpec, DeviceListSpec, DeviceRetrieveSpec, DeviceSpecBase +1

## metadata

- shape unknown — no spec declares this field (check serializers; default is dict)

## definitions

- `ContactPoint`: {system: ContactPointSystemChoices, value: str, use: ContactPointUseChoices}
- `ContactPointSystemChoices`: 'phone' | 'fax' | 'email' | 'pager' | 'url' | 'sms' | 'other'
- `ContactPointUseChoices`: 'home' | 'work' | 'temp' | 'old' | 'mobile'
