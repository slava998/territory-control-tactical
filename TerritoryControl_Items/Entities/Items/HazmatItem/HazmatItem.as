void onInit(CBlob@ this)
{
	this.set_string("required class", "hazmat");
	this.set_Vec2f("class offset", Vec2f(0, 0));
	
	this.Tag("kill on use");
	this.Tag("classchanger");
	this.Tag("RemoveOnCleaning");
}

void GetButtonsFor(CBlob@ this, CBlob@ caller)
{
	if (this.getDistanceTo(caller) > 96.0f) return;
	bool canChangeClass = caller.getName() != "hazmat";

	if(canChangeClass)
	{
		this.Untag("class button disabled");
	}
	else
	{
		this.Tag("class button disabled");
	}
}