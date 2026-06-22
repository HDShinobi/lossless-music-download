package server

import (
	"encoding/xml"
	"fmt"
)

// deviceDescriptionXML returns the UPnP root device description XML.
func deviceDescriptionXML(friendlyName, udn, baseURL string) []byte {
	type specVersion struct {
		Major int `xml:"major"`
		Minor int `xml:"minor"`
	}
	type service struct {
		ServiceType string `xml:"serviceType"`
		ServiceID   string `xml:"serviceId"`
		SCPDURL     string `xml:"SCPDURL"`
		ControlURL  string `xml:"controlURL"`
		EventSubURL string `xml:"eventSubURL"`
	}
	type serviceList struct {
		Services []service `xml:"service"`
	}
	type device struct {
		DeviceType   string      `xml:"deviceType"`
		FriendlyName string      `xml:"friendlyName"`
		Manufacturer string      `xml:"manufacturer"`
		ModelName    string      `xml:"modelName"`
		UDN          string      `xml:"UDN"`
		ServiceList  serviceList `xml:"serviceList"`
	}
	type root struct {
		XMLName     xml.Name    `xml:"urn:schemas-upnp-org:device-1-0 root"`
		SpecVersion specVersion `xml:"specVersion"`
		URLBase     string      `xml:"URLBase"`
		Device      device      `xml:"device"`
	}

	doc := root{
		SpecVersion: specVersion{Major: 1, Minor: 0},
		URLBase:     baseURL,
		Device: device{
			DeviceType:   "urn:schemas-upnp-org:device:MediaServer:1",
			FriendlyName: friendlyName,
			Manufacturer: "LosslessMusic",
			ModelName:    "LosslessMusic MediaServer",
			UDN:          udn,
			ServiceList: serviceList{
				Services: []service{
					{
						ServiceType: "urn:schemas-upnp-org:service:ContentDirectory:1",
						ServiceID:   "urn:upnp-org:serviceId:ContentDirectory",
						SCPDURL:     "/cd/scpd",
						ControlURL:  "/cd/control",
						EventSubURL: "/cd/event",
					},
				},
			},
		},
	}

	out, err := xml.MarshalIndent(doc, "", "  ")
	if err != nil {
		panic(fmt.Sprintf("deviceDescriptionXML: %v", err))
	}
	return append([]byte(xml.Header), out...)
}

// contentDirectorySCPD returns the ContentDirectory SCPD XML advertising the Browse action.
func contentDirectorySCPD() []byte {
	const scpd = `<?xml version="1.0"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <actionList>
    <action>
      <name>Browse</name>
      <argumentList>
        <argument><name>ObjectID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_ObjectID</relatedStateVariable></argument>
        <argument><name>BrowseFlag</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_BrowseFlag</relatedStateVariable></argument>
        <argument><name>Filter</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_Filter</relatedStateVariable></argument>
        <argument><name>StartingIndex</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_Index</relatedStateVariable></argument>
        <argument><name>RequestedCount</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_Count</relatedStateVariable></argument>
        <argument><name>SortCriteria</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_SortCriteria</relatedStateVariable></argument>
        <argument><name>Result</name><direction>out</direction><relatedStateVariable>A_ARG_TYPE_Result</relatedStateVariable></argument>
        <argument><name>NumberReturned</name><direction>out</direction><relatedStateVariable>A_ARG_TYPE_Count</relatedStateVariable></argument>
        <argument><name>TotalMatches</name><direction>out</direction><relatedStateVariable>A_ARG_TYPE_Count</relatedStateVariable></argument>
        <argument><name>UpdateID</name><direction>out</direction><relatedStateVariable>A_ARG_TYPE_UpdateID</relatedStateVariable></argument>
      </argumentList>
    </action>
  </actionList>
  <serviceStateTable>
    <stateVariable sendEvents="no"><name>A_ARG_TYPE_ObjectID</name><dataType>string</dataType></stateVariable>
    <stateVariable sendEvents="no"><name>A_ARG_TYPE_Result</name><dataType>string</dataType></stateVariable>
    <stateVariable sendEvents="no"><name>A_ARG_TYPE_BrowseFlag</name><dataType>string</dataType><allowedValueList><allowedValue>BrowseMetadata</allowedValue><allowedValue>BrowseDirectChildren</allowedValue></allowedValueList></stateVariable>
    <stateVariable sendEvents="no"><name>A_ARG_TYPE_Filter</name><dataType>string</dataType></stateVariable>
    <stateVariable sendEvents="no"><name>A_ARG_TYPE_SortCriteria</name><dataType>string</dataType></stateVariable>
    <stateVariable sendEvents="no"><name>A_ARG_TYPE_Index</name><dataType>ui4</dataType></stateVariable>
    <stateVariable sendEvents="no"><name>A_ARG_TYPE_Count</name><dataType>ui4</dataType></stateVariable>
    <stateVariable sendEvents="no"><name>A_ARG_TYPE_UpdateID</name><dataType>ui4</dataType></stateVariable>
    <stateVariable sendEvents="yes"><name>SystemUpdateID</name><dataType>ui4</dataType></stateVariable>
    <stateVariable sendEvents="yes"><name>ContainerUpdateIDs</name><dataType>string</dataType></stateVariable>
  </serviceStateTable>
</scpd>`
	return []byte(scpd)
}
