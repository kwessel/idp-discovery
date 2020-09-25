<?php // Copyright (c) 2015, SWITCH ?>

<?php require_once('custom-templates.php'); ?>
<!-- Identity Provider Selection: Start -->
        <h1>Select Your University</h1>

    <p class="text">

    <?php
	echo ('This service');
	if (isset($serviceName))
	{
	    echo (', '.$serviceName.', ');
	}
    ?>
    supports multiple groups associated with the University of Illinois System. Select one of the following to go to the appropriate login screen.
    </p>

    <div class="list">

<form id="IdPList" name="IdPList" method="post" onSubmit="return checkForm()" action="<?php echo $actionURL ?>">
	<fieldset class="no-border">
        <legend><h2>Choose from the following:</h2></legend>

	<div id="userIdPSelection"> 
	<?php printRadioList($IDProviders, $selectedIDP) ?>
	</div>
	</fieldset>
	<input type="submit" name="Select" accesskey="s" value="<?php echo getLocalString('select_button') ?>"> 
		<?php if ($showPermanentSetting) : ?>
		<!-- Value permanent must be a number which is equivalent to the days the cookie should be valid -->
		<input type="checkbox" name="permanent" id="rememberPermanent" value="3650">
		<label for="rememberPermanent">Remember my choice</label>
		<?php endif ?>
</form>
	</div>

<!-- Identity Provider Selection: End -->
