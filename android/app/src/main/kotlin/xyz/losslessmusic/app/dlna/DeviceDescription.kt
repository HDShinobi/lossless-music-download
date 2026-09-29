package xyz.losslessmusic.app.dlna

import java.security.MessageDigest

internal object DeviceDescription {
    fun xml(friendlyName: String, udn: String, baseUrl: String): String = buildString {
        append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        append("<root xmlns=\"urn:schemas-upnp-org:device-1-0\">\n")
        append("  <specVersion>\n")
        append("    <major>1</major>\n")
        append("    <minor>0</minor>\n")
        append("  </specVersion>\n")
        append("  <URLBase>${Xml.escape(baseUrl)}</URLBase>\n")
        append("  <device>\n")
        append("    <deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>\n")
        append("    <friendlyName>${Xml.escape(friendlyName)}</friendlyName>\n")
        append("    <manufacturer>LosslessMusic</manufacturer>\n")
        append("    <modelName>LosslessMusic MediaServer</modelName>\n")
        append("    <UDN>${Xml.escape(udn)}</UDN>\n")
        append("    <serviceList>\n")
        append("      <service>\n")
        append("        <serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>\n")
        append("        <serviceId>urn:upnp-org:serviceId:ContentDirectory</serviceId>\n")
        append("        <SCPDURL>/cd/scpd</SCPDURL>\n")
        append("        <controlURL>/cd/control</controlURL>\n")
        append("        <eventSubURL>/cd/event</eventSubURL>\n")
        append("      </service>\n")
        append("    </serviceList>\n")
        append("  </device>\n")
        append("</root>")
    }

    fun contentDirectoryScpd(): String = """<?xml version="1.0"?>
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
</scpd>"""

    fun stableUdn(name: String, rootDir: String): String {
        val digest = MessageDigest.getInstance("SHA-1")
        digest.update(name.toByteArray(Charsets.UTF_8))
        digest.update(0)
        digest.update(rootDir.toByteArray(Charsets.UTF_8))
        val bytes = digest.digest().copyOfRange(0, 16)
        bytes[6] = ((bytes[6].toInt() and 0x0f) or 0x50).toByte()
        bytes[8] = ((bytes[8].toInt() and 0x3f) or 0x80).toByte()
        val hex = bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
        return "uuid:${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}"
    }
}
