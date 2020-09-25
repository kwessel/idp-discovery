<?php // Copyright (c) 2015, SWITCH ?>

<!-- Identity Provider Selection: Start -->
<h1>Confirm campus selection</h1> 

    <p class="text">
    You have selected <?php echo $permanentUserIdPName ?> as your
    campus. You have also chosen to have your selection remembered so
    you won't be asked again while accessing services with this browser.
    </p>
    
<form id="IdPList" name="IdPList" method="post" onSubmit="return checkForm()" action="<?php echo $actionURL ?>">
				<input type=hidden name="permanent_user_idp" value="<?php echo $permanentUserIdP ?>">
			<?php if (isValidShibRequest()) : ?>
			<input class="btn" type="submit" accesskey="s" name="Select" name="permanent" value="<?php echo getLocalString('goto_sp') ?>">
			<?php endif ?>
			<input class="btn" type="submit" accesskey="c"
			name="clear_user_idp" value="Choose a different campus">
			<p>
			<?php $scriptURL = "https://".$_SERVER['HTTP_HOST']."/discovery/DS" ?>
			<?php $fullURL = "<br /><a href=".$scriptURL.">".$scriptURL."</a>" ?>
			You can change your campus selection later by
			visiting
			<?php echo $fullURL; ?>
			</p>
</form>

<!-- Identity Provider Selection: End -->
