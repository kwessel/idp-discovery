<?xml version="1.0" encoding="UTF-8"?>
<!--
	Copyright 2017 Internet2

	Licensed under the Apache License, Version 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at

		http://www.apache.org/licenses/LICENSE-2.0

	Unless required by applicable law or agreed to in writing, software
	distributed under the License is distributed on an "AS IS" BASIS,
	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	See the License for the specific language governing permissions and
	limitations under the License.
-->
<!--
	entities_timestamps_txt.xsl
	
	An XSL transform that takes a SAML V2.0 metadata file as input.
	The root element of the metadata file is an md:EntitiesDescriptor 
	element. The script returns the following single line of output:
	
	  @ID @creationInstant @validUntil
	
	where each of the fields is separated by a tab character.
-->
<xsl:stylesheet version="1.0"
	xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
	xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata"
	xmlns:mdrpi="urn:oasis:names:tc:SAML:metadata:rpi">
	
	<!-- output is plain text -->
	<xsl:output method="text"/>

    <xsl:template match="/md:EntitiesDescriptor">
    	<xsl:value-of select="./@ID"/>
    	<xsl:text>&#x09;</xsl:text>
    	<xsl:value-of select="./md:Extensions/mdrpi:PublicationInfo/@creationInstant"/>
    	<xsl:text>&#x09;</xsl:text>
    	<xsl:value-of select="./@validUntil"/>
    	<xsl:text>&#x0a;</xsl:text>
    </xsl:template>

	<xsl:template match="text()">
		<!-- do nothing -->
	</xsl:template>
</xsl:stylesheet>
