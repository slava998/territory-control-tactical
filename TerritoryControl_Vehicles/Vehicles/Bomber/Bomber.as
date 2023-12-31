#include "VehicleCommon.as"
#include "Hitters.as"
#include "Explosion.as";

//most of the code is in BomberCommon.as

void onInit(CBlob@ this)
{
	Vehicle_Setup(this,
	              44.0f, // move speed
	              0.19f,  // turn speed
	              Vec2f(0.0f, -5.0f), // jump out velocity
	              true  // inventory access
	             );

	VehicleInfo@ v;
	if (!this.get("VehicleInfo", @v)) return;

	Vehicle_SetupAirship(this, v, 50.0f);

	this.Tag("vehicle");
	this.Tag("bomber");

	this.getShape().SetOffset(Vec2f(0, 10));
	this.getShape().SetRotationsAllowed(false);

	this.set_f32("max_fuel", 2000);
	this.set_Vec2f("gyro_button_pos", Vec2f(0, -12));
	this.set_f32("fuel_consumption_modifier", 1.0f);
}

void onDie(CBlob@ this)
{
	if (isServer())
	{
		CBlob@ wreck = server_CreateBlobNoInit("bomberwreck");
		wreck.setPosition(this.getPosition());
		wreck.setVelocity(this.getVelocity());
		wreck.setAngleDegrees(this.getAngleDegrees());
		wreck.server_setTeamNum(this.getTeamNum());
		wreck.Init();

		for (int i = 0; i < 5 + XORRandom(3); i++)
		{
			CBlob@ blob = server_CreateBlob("flame", -1, this.getPosition());
			blob.setVelocity(Vec2f(XORRandom(10) - 5, -XORRandom(6)));
			blob.server_SetTimeToDie(4 + XORRandom(15));
		}
	}
}

//required shit
void Vehicle_onFire(CBlob@ this, VehicleInfo@ v, CBlob@ bullet, const u8 charge)
{
	
}
/*
bool isInventoryAccessible(CBlob@ this, CBlob@ byBlob)
{
	CBlob@ carried = byBlob.getCarriedBlob();
	if (carried !is null){
		if (carried.getName() != "gyromat")
		return false;
	}
	return true;
}
*/
bool isInventoryAccessible(CBlob@ this,CBlob@ forBlob)
{
	return forBlob.getCarriedBlob().getName()!="gyromat";
}

bool Vehicle_canFire(CBlob@ this, VehicleInfo@ v, bool isActionPressed, bool wasActionPressed, u8 &out chargeValue)
{
	return true;
}

bool doesCollideWithBlob(CBlob@ this, CBlob@ blob)
{
	return Vehicle_doesCollideWithBlob_ground(this, blob);
}

bool canBePickedUp(CBlob@ this, CBlob@ byBlob)
{
	return false;
}

//SPRITE
void onInit(CSprite@ this)
{
	this.SetZ(-50.0f);
	this.getCurrentScript().tickFrequency = 5;

	CSpriteLayer@ balloon = this.addSpriteLayer("balloon", "Balloon.png", 48, 64);
	if (balloon !is null)
	{
		balloon.addAnimation("default", 0, false);
		int[] frames = { 0, 2, 3 };
		balloon.animation.AddFrames(frames);
		balloon.SetRelativeZ(1.0f);
		balloon.SetOffset(Vec2f(0.0f, -26.0f));
	}

	CSpriteLayer@ background = this.addSpriteLayer("background", "Balloon.png", 32, 16);
	if (background !is null)
	{
		background.addAnimation("default", 0, false);
		background.animation.AddFrame(3);
		background.SetRelativeZ(-5.0f);
		background.SetOffset(Vec2f(0.0f, -5.0f));
	}

	CSpriteLayer@ burner = this.addSpriteLayer("burner", "Balloon.png", 8, 16);
	if (burner !is null)
	{
		{
			Animation@ a = burner.addAnimation("default", 3, true);
			int[] frames = { 41, 42, 43 };
			a.AddFrames(frames);
		}
		{
			Animation@ a = burner.addAnimation("up", 3, true);
			int[] frames = { 38, 39, 40 };
			a.AddFrames(frames);
		}
		{
			Animation@ a = burner.addAnimation("down", 3, true);
			int[] frames = { 44, 45, 44, 46 };
			a.AddFrames(frames);
		}
		burner.SetRelativeZ(1.5f);
		burner.SetOffset(Vec2f(0.0f, -26.0f));
	}
}

void onAttach(CBlob@ this, CBlob@ attached, AttachmentPoint @attachedPoint)
{
	if (attached !is null)
	{
		if (attached.hasTag("flesh") || attached.hasTag("human") || attached.hasTag("hooman"))
		{ 
			if (isServer())
			{	
				attached.Tag("invincible");
				attached.Tag("invincibilityByVehicle");
			}
		}
	}
}

void onDetach(CBlob@ this, CBlob@ detached, AttachmentPoint @attachedPoint)
{
	if (detached !is null)
	{
		detached.Untag("invincible");
		detached.Untag("invincibilityByVehicle");
	}
}

void onTick(CSprite@ this)
{
	CBlob@ blob = this.getBlob();
	f32 ratio = 1.0f - (blob.getHealth() / blob.getInitialHealth());
	this.animation.setFrameFromRatio(ratio);

	CSpriteLayer@ balloon = this.getSpriteLayer("balloon");
	if (balloon !is null)
	{
		if (blob.getHealth() > 1.0f)
			balloon.animation.frame = Maths::Min((ratio) * 3, 1.0f);
		else
			balloon.animation.frame = 2;
	}

	CSpriteLayer@ burner = this.getSpriteLayer("burner");
	if (burner !is null)
	{
		burner.SetOffset(Vec2f(0.0f, -14.0f));
		s8 dir = blob.get_s8("move_direction");
		if (dir == 0)
		{
			blob.SetLightColor(SColor(255, 255, 240, 171));
			burner.SetAnimation("default");
		}
		else if (dir < 0)
		{
			blob.SetLightColor(SColor(255, 255, 240, 200));
			burner.SetAnimation("up");
		}
		else if (dir > 0)
		{
			blob.SetLightColor(SColor(255, 255, 200, 171));
			burner.SetAnimation("down");
		}
	}
}
