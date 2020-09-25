<?php
function printRadioList($IDProviders, $selectedIDP = ''){
	global $language;
	
	foreach ($IDProviders as $key => $values){
		
		// Get IdP Name
		$IdPName = (isset($values[$language]['Name'])) ? $values[$language]['Name'] : $IdPName = $values['Name'];
		
		// Figure out if entry is valid or a category
		if (!isset($values['SSO'])){
			continue;
		}
		
		echo "\n\t<p class=\"campus-list-item\">".printRadioElement($IDProviders, $key, $selectedIDP)."</p>";
		
	}
	
}

function printRadioElement($IDProviders, $key, $selectedIDP){
	global $language;
	
	$htmlToReturn = '';

	// Return if IdP does not exist
	if (!isset($IDProviders[$key])){
		return '';
	}
	
	// Get values
	$values = $IDProviders[$key];
	
	// Get IdP Name
	$IdPName = (isset($values[$language]['Name'])) ? $values[$language]['Name'] : $IdPName = $values['Name'];
	
	// Set selected attribute
	$selected = ($selectedIDP == $key) ? ' checked="checked"' : $selected = '';
	
	// Add additional information as data attribute to the entry
	$data = getDomainNameFromURI($key);
	$data .= composeOptionData($values);
	
	// Add logo (which is assumed to be 16x16px) to extension string
	$logo =  (isset($values['Logo'])) ? 'logo="'.$values['Logo']['URL']. '"' : '' ;
	
	return '<input type="radio" name="user_idp" value="'.$key.'" id="'.$key.'"'.$selected.' data="'.htmlspecialchars($data).'" '.$logo.'><label for="'.$key.'">'.$IdPName.'</label>';
}

?>
