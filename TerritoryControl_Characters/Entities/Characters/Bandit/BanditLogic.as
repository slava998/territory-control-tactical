// Knight logic

#include "ThrowCommon.as"
#include "KnightCommon.as";
#include "RunnerCommon.as";
#include "Hitters.as";
#include "ShieldCommon.as";
#include "Knocked.as"
#include "Help.as";
#include "Requirements.as"
#include "CustomBlocks.as";


//attacks limited to the one time per-actor before reset.

void knight_actorlimit_setup(CBlob@ this)
{
	u16[] networkIDs;
	this.set("LimitedActors", networkIDs);
}

bool knight_has_hit_actor(CBlob@ this, CBlob@ actor)
{
	u16[]@ networkIDs;
	this.get("LimitedActors", @networkIDs);
	return networkIDs.find(actor.getNetworkID()) >= 0;
}

u32 knight_hit_actor_count(CBlob@ this)
{
	u16[]@ networkIDs;
	this.get("LimitedActors", @networkIDs);
	return networkIDs.length;
}

void knight_add_actor_limit(CBlob@ this, CBlob@ actor)
{
	this.push("LimitedActors", actor.getNetworkID());
}

void knight_clear_actor_limits(CBlob@ this)
{
	this.clear("LimitedActors");
}

void onInit(CBlob@ this)
{
	KnightInfo knight;

	knight.state = KnightStates::normal;
	knight.swordTimer = 0;
	knight.slideTime = 0;
	knight.doubleslash = false;
	knight.tileDestructionLimiter = 0;

	this.set("knightInfo", @knight);

	this.set_f32("gib health", -3.0f);
	knight_actorlimit_setup(this);
	this.getShape().SetRotationsAllowed(false);
	this.getShape().getConsts().net_threshold_multiplier = 0.5f;
	
	this.Tag("player");
	this.Tag("flesh");
	this.Tag("neutral");
	this.Tag("human");

	this.set_u8("override head", 68);
	
	this.addCommandID("get bomb");
	
	this.set_u8("bomb type", 255);
	for (uint i = 0; i < bombTypeNames.length; i++)
	{
		this.addCommandID("pick " + bombTypeNames[i]);
	}

	//centered on bomb select
	//this.set_Vec2f("inventory offset", Vec2f(0.0f, 122.0f));
	//centered on inventory
	this.set_Vec2f("inventory offset", Vec2f(0.0f, 0.0f));

	SetHelp(this, "help self action", "knight", "$Jab$Jab        $LMB$", "", 4);

	this.getCurrentScript().runFlags |= Script::tick_not_attached;
	this.getCurrentScript().removeIfTag = "dead";

	this.set_u32("timer", 0);
}

void onSetPlayer(CBlob@ this, CPlayer@ player)
{
	if (player !is null) player.SetScoreboardVars("ScoreboardIcons.png", 5, Vec2f(16, 16));
}

void onTick(CBlob@ this)
{
	if (this.get_u32("timer") > 1) this.set_u32("timer", this.get_u32("timer") - 1);

	RunnerMoveVars@ moveVars;
	if (!this.get("moveVars", @moveVars))
	{
		return;
	}

	if (this.hasTag("glued") && this.get_u32("timer") > 1)
	{
		moveVars.walkFactor *= 0.4f;
		moveVars.jumpFactor *= 0.5f;
	}
	
	u8 knocked = getKnocked(this);

	if (this.isInInventory())
		return;

	//knight logic stuff
	//get the vars to turn various other scripts on/off
	//RunnerMoveVars@ moveVars;
	if (!this.get("moveVars", @moveVars))
	{
		return;
	}

	KnightInfo@ knight;
	if (!this.get("knightInfo", @knight))
	{
		return;
	}

	Vec2f pos = this.getPosition();
	Vec2f vel = this.getVelocity();
	Vec2f aimpos = this.getAimPos();
	const bool inair = (!this.isOnGround() && !this.isOnLadder());

	Vec2f vec;

	const int direction = this.getAimDirection(vec);
	const f32 side = (this.isFacingLeft() ? 1.0f : -1.0f);

	bool swordState = isSwordState(knight.state);
	bool pressed_a1 = this.isKeyPressed(key_action1) && !this.hasTag("noLMB") && !(this.get_f32("babbyed") > 0);
	bool pressed_a2 = this.isKeyPressed(key_action2) && !(this.get_f32("babbyed") > 0) && !this.hasTag("noRMB");
	bool walking = (this.isKeyPressed(key_left) || this.isKeyPressed(key_right));

	const bool myplayer = this.isMyPlayer();

	moveVars.jumpFactor *= 1.2f;
	moveVars.walkFactor *= 1.1f;
	
	//with the code about menus and myplayer you can slash-cancel;
	//we'll see if knights dmging stuff while in menus is a real issue and go from there
	if (knocked > 0 || (myplayer && getHUD().hasMenus()))// || myplayer && getHUD().hasMenus())
	{
		knight.state = KnightStates::normal; //cancel any attacks or shielding
		knight.swordTimer = 0;
		knight.slideTime = 0;
		knight.doubleslash = false;

		pressed_a1 = false;
		pressed_a2 = false;
		walking = false;

	}
	else if ((pressed_a1 || swordState) && !moveVars.wallsliding)   //no attacking during a slide
	{
		if (isClient())
		{
			if (knight.swordTimer == KnightVars::slash_charge_level2)
			{
				Sound::Play("AnimeSword.ogg", pos, myplayer ? 1.3f : 0.7f);
			}
			else if (knight.swordTimer == KnightVars::slash_charge)
			{
				Sound::Play("SwordSheath.ogg", pos, myplayer ? 1.3f : 0.7f);
			}
		}

		if (knight.swordTimer > KnightVars::slash_charge_limit)
		{
			Sound::Play("/Stun", pos, 1.0f, this.getSexNum() == 0 ? 1.0f : 2.0f);
			SetKnocked(this, 15);
		}

		bool strong = (knight.swordTimer > KnightVars::slash_charge_level2);
		moveVars.jumpFactor *= (strong ? 0.6f : 0.8f);
		moveVars.walkFactor *= (strong ? 0.8f : 0.9f);

		if (!inair)
		{
			this.AddForce(Vec2f(vel.x * -5.0, 0.0f));   //horizontal slowing force (prevents SANICS)
		}

		if (knight.state == KnightStates::normal || (this.isKeyJustPressed(key_action1) && !this.hasTag("noLMB")) &&!inMiddleOfAttack(knight.state))
		{
			knight.state = KnightStates::sword_drawn;
			knight.swordTimer = 0;
		}

		if (knight.state == KnightStates::sword_drawn && isServer())
		{
			knight_clear_actor_limits(this);
		}
		
		//responding to releases/noaction
		s32 delta = knight.swordTimer;
		if (knight.swordTimer < 128)
			knight.swordTimer++;

		if (knight.state == KnightStates::sword_drawn && !pressed_a1 && !(this.isKeyJustReleased(key_action1) && !this.hasTag("noLMB")) && delta > KnightVars::resheath_time)
		{
			knight.state = KnightStates::normal;
		}
		else if((this.isKeyJustReleased(key_action1) && !this.hasTag("noLMB")) && knight.state == KnightStates::sword_drawn)
		{
			knight.swordTimer = 0;

			if (delta < KnightVars::slash_charge)
			{
				if (direction == -1)
				{
					knight.state = KnightStates::sword_cut_up;
				}
				else if (direction == 0)
				{
					if (aimpos.y < pos.y)
					{
						knight.state = KnightStates::sword_cut_mid;
					}
					else
					{
						knight.state = KnightStates::sword_cut_mid_down;
					}
				}
				else
				{
					knight.state = KnightStates::sword_cut_down;
				}
			}
			else if (delta < KnightVars::slash_charge_level2)
			{
				knight.state = KnightStates::sword_power;
				Vec2f aiming_direction = vel;
				aiming_direction.y *= 2;
				aiming_direction.Normalize();
				knight.slash_direction = aiming_direction;
			}
			else if (delta < KnightVars::slash_charge_limit)
			{
				knight.state = KnightStates::sword_power_super;
				Vec2f aiming_direction = vel;
				aiming_direction.y *= 2;
				aiming_direction.Normalize();
				knight.slash_direction = aiming_direction;
			}
			else
			{
				//knock?
			}
		}
		else if (knight.state >= KnightStates::sword_cut_mid &&
		         knight.state <= KnightStates::sword_cut_down) // cut state
		{
			if (delta == DELTA_BEGIN_ATTACK)
			{
				Sound::Play("/SwordSlash", this.getPosition());
			}

			if (delta > DELTA_BEGIN_ATTACK && delta < DELTA_END_ATTACK)
			{
				f32 attackarc = 90.0f;
				f32 attackAngle = getCutAngle(this, knight.state);

				if (knight.state == KnightStates::sword_cut_down)
				{
					attackarc *= 0.9f;
				}

				DoAttack(this, 1.50f, attackAngle, attackarc, Hitters::stab, delta, knight);
			}
			else if (delta >= 9)
			{
				knight.swordTimer = 0;
				knight.state = KnightStates::sword_drawn;
			}
		}
		else if (knight.state == KnightStates::sword_power || knight.state == KnightStates::sword_power_super)
		{
			//setting double
			if (knight.state == KnightStates::sword_power_super && ((this.isKeyJustPressed(key_action1) && !this.hasTag("noLMB")) && !this.hasTag("noLMB")))
			{
				knight.doubleslash = true;
			}

			//attacking + noises
			if (delta == 2)
			{
				Sound::Play("/ArgLong", this.getPosition());
				Sound::Play("/SwordSlash", this.getPosition());
			}
			else if (delta > DELTA_BEGIN_ATTACK && delta < 10)
			{
				DoAttack(this, 2.0f, -(vec.Angle()), 120.0f, Hitters::stab, delta, knight);
			}
			else if (delta >= KnightVars::slash_time ||
			         (knight.doubleslash && delta >= KnightVars::double_slash_time))
			{
				knight.swordTimer = 0;

				if (knight.doubleslash)
				{
					knight_clear_actor_limits(this);
					knight.doubleslash = false;
					knight.state = KnightStates::sword_power;
				}
				else
				{
					knight.state = KnightStates::sword_drawn;
				}
			}
		}

		//special slash movement

		if ((knight.state == KnightStates::sword_power ||
		        knight.state == KnightStates::sword_power_super) &&
		        delta < KnightVars::slash_move_time)
		{

			if (Maths::Abs(vel.x) < KnightVars::slash_move_max_speed &&
			        vel.y > -KnightVars::slash_move_max_speed)
			{
				Vec2f slash_vel =  knight.slash_direction * this.getMass() * 0.5f;
				this.AddForce(slash_vel);
			}
		}

		moveVars.canVault = false;

	}
	else if (pressed_a2)
	{
		if (getGameTime() > this.get_u32("leap timer"))
		{
			this.AddForce(Vec2f(vel.x * -5.0, 0.0f));   //horizontal slowing force (prevents SANICS)
			
			if (this.isKeyPressed(key_action2))
			{
				Vec2f velocity = this.getAimPos() - this.getPosition();
				velocity.Normalize();
				// velocity.y *= 0.5f;
				
				this.setVelocity(velocity * 6);
				this.getSprite().PlaySound("ArgLong");
				this.set_u32("leap timer", getGameTime() + 40);
			}
		}
	}
	else if (this.isKeyJustReleased(key_action2) || (this.isKeyJustReleased(key_action1) && !this.hasTag("noLMB")) || this.get_u32("knight_timer") <= getGameTime())
	{
		knight.state = KnightStates::normal;
	}
	
	
		
	
	

	//throwing bombs

	if (myplayer)
	{
		// space

		if (this.isKeyJustPressed(key_action3))
		{
			CBlob@ carried = this.getCarriedBlob();
			bool holding = carried !is null;// && carried.hasTag("exploding");

			CInventory@ inv = this.getInventory();
			bool thrown = false;
			u8 bombType = this.get_u8("bomb type");
			if (bombType == 255)
			{
				SetFirstAvailableBomb(this);
				bombType = this.get_u8("bomb type");
			}
			if (bombType < bombTypeNames.length)
			{
				for (int i = 0; i < inv.getItemsCount(); i++)
				{
					CBlob@ item = inv.getItem(i);
					if(item !is null)
					{
						const string itemname = item.getName();
						if (!holding && bombTypeNames[bombType] == itemname)
						{
							if (bombType >= 2)
							{
								this.server_Pickup(item);
								client_SendThrowOrActivateCommand(this);
								thrown = true;
							}
							else
							{
								CBitStream params;
								params.write_u8(bombType);
								this.SendCommand(this.getCommandID("get bomb"), params);
								thrown = true;
							}
							break;
						}
					}
				}
			}

			if (!thrown)
			{
				client_SendThrowOrActivateCommand(this);
				SetFirstAvailableBomb(this);
			}
		}

		// help

		if((this.isKeyJustPressed(key_action1) && !this.hasTag("noLMB")) && getGameTime() > 150)
		{
			SetHelp(this, "help self action", "knight", "$Slash$ Slash!    $KEY_HOLD$$LMB$", "", 13);
		}
	}

	if (!swordState && isServer())
	{
		knight_clear_actor_limits(this);
	}
}

void onCommand(CBlob@ this, u8 cmd, CBitStream @params)
{
	if (cmd == this.getCommandID("get bomb"))
	{
		const u8 bombType = params.read_u8();
		if (bombType >= bombTypeNames.length)
			return;

		const string bombTypeName = bombTypeNames[bombType];
		this.Tag(bombTypeName + " done activate");
		if (hasItem(this, bombTypeName))
		{
			if (bombType == 0)
			{
				if (isServer())
				{
					CBlob @blob = server_CreateBlob("bomb", this.getTeamNum(), this.getPosition());
					if (blob !is null && this !is null)
					{
						TakeItem(this, bombTypeName);
						this.server_Pickup(blob);
					}
				}
			}
			else if (bombType == 1)
			{
				if (isServer())
				{
					CBlob @blob = server_CreateBlob("waterbomb", this.getTeamNum(), this.getPosition());
					if (blob !is null && this !is null)
					{
						TakeItem(this, bombTypeName);
						this.server_Pickup(blob);
						blob.set_f32("map_damage_ratio", 0.0f);
						blob.set_f32("explosive_damage", 0.0f);
						blob.set_f32("explosive_radius", 92.0f);
						blob.set_bool("map_damage_raycast", false);
						blob.set_string("custom_explosion_sound", "/GlassBreak");
						blob.set_u8("custom_hitter", Hitters::water);
                        blob.Tag("splash ray cast");

					}
				}
			}
			else
			{
			}

			SetFirstAvailableBomb(this);
		}
	}
	else if (cmd == this.getCommandID("cycle"))  //from standardcontrols
	{
		// cycle arrows
		u8 type = this.get_u8("bomb type");
		int count = 0;
		while (count < bombTypeNames.length)
		{
			type++;
			count++;
			if (type >= bombTypeNames.length)
				type = 0;
			if (this.getBlobCount(bombTypeNames[type]) > 0)
			{
				this.set_u8("bomb type", type);
				if (this.isMyPlayer())
				{
					Sound::Play("/CycleInventory.ogg");
				}
				break;
			}
		}
	}
	else if (cmd == this.getCommandID("activate/throw"))
	{
		SetFirstAvailableBomb(this);
	}
	else
	{
		for (uint i = 0; i < bombTypeNames.length; i++)
		{
			if (cmd == this.getCommandID("pick " + bombTypeNames[i]))
			{
				this.set_u8("bomb type", i);
				break;
			}
		}
	}
}


f32 onHit(CBlob@ this, Vec2f worldPoint, Vec2f velocity, f32 damage, CBlob@ hitterBlob, u8 customData)
{
	CPlayer@ player=this.getPlayer();
	if(this.hasTag("invincible") || (player !is null && player.freeze)) {
		return 0;
	}
	// play cling sound if other knight attacked us
	// dmg could be taken out here if we ever want to

	if (hitterBlob.getPosition().x < this.getPosition().x && hitterBlob.getName() == "knight") // knight and the left one (to play only once)
	{
		CSprite@ sprite = this.getSprite();
		CSprite@ hsprite = hitterBlob.getSprite();

		if (hsprite.isAnimation("strike_power_ready") || hsprite.isAnimation("strike_mid") ||
		        hsprite.isAnimation("strike_mid_down") || hsprite.isAnimation("strike_up") ||
		        hsprite.isAnimation("strike_down") || hsprite.isAnimation("strike_up"))
		{
			if (sprite.isAnimation("strike_power_ready") || sprite.isAnimation("strike_mid") ||
			        sprite.isAnimation("strike_mid_down") || sprite.isAnimation("strike_up") ||
			        sprite.isAnimation("strike_down") || sprite.isAnimation("strike_up"))
			{
				this.getSprite().PlaySound("SwordCling");
			}
		}
	}

	return damage; //no block, damage goes through
}

/////////////////////////////////////////////////

bool isJab(f32 damage)
{
	return damage < 1.5f;
}

void DoAttack(CBlob@ this, f32 damage, f32 aimangle, f32 arcdegrees, u8 type, int deltaInt, KnightInfo@ info)
{
	if (!isServer())
	{
		return;
	}

	if (aimangle < 0.0f)
	{
		aimangle += 360.0f;
	}

	Vec2f blobPos = this.getPosition();
	Vec2f vel = this.getVelocity();
	Vec2f thinghy(1, 0);
	thinghy.RotateBy(aimangle);
	Vec2f pos = blobPos - thinghy * 6.0f + vel + Vec2f(0, -2);
	vel.Normalize();

	f32 attack_distance = Maths::Min(DEFAULT_ATTACK_DISTANCE + Maths::Max(0.0f, 1.75f * this.getShape().vellen * (vel * thinghy)), MAX_ATTACK_DISTANCE);

	f32 radius = this.getRadius();
	CMap@ map = this.getMap();
	bool dontHitMore = false;
	bool dontHitMoreMap = false;
	const bool jab = isJab(damage);

	//get the actual aim angle
	f32 exact_aimangle = (this.getAimPos() - blobPos).Angle();

	// this gathers HitInfo objects which contain blob or tile hit information
	HitInfo@[] hitInfos;
	if (map.getHitInfosFromArc(pos, aimangle, arcdegrees, radius + attack_distance, this, @hitInfos))
	{
		//HitInfo objects are sorted, first come closest hits
		for (uint i = 0; i < hitInfos.length; i++)
		{
			HitInfo@ hi = hitInfos[i];
			CBlob@ b = hi.blob;
			if (b !is null && !dontHitMore) // blob
			{
				if (b.hasTag("ignore sword")) continue;

				//big things block attacks
				const bool large = b.hasTag("blocks sword") && !b.isAttached() && b.isCollidable();

				if (!canHit(this, b))
				{
					// no TK
					if (large)
						dontHitMore = true;

					continue;
				}

				if (knight_has_hit_actor(this, b))
				{
					if (large)
						dontHitMore = true;

					continue;
				}

				knight_add_actor_limit(this, b);
				if (!dontHitMore)
				{
					Vec2f velocity = b.getPosition() - pos;
					this.server_Hit(b, hi.hitpos, velocity, damage, type, true);  // server_Hit() is server-side only

					// end hitting if we hit something solid, don't if its flesh
					if (large)
					{
						dontHitMore = true;
					}
				}
			}
			else  // hitmap
				if (!dontHitMoreMap && (deltaInt == DELTA_BEGIN_ATTACK + 1))
				{
					bool ground = map.isTileGround(hi.tile);
					bool dirt_stone = map.isTileStone(hi.tile);
					bool gold = map.isTileGold(hi.tile);
					bool wood = map.isTileWood(hi.tile);
					bool glass = ((hi.tile >= CMap::tile_glass && hi.tile <= CMap::tile_glass_d0) ? true : false);
					bool tnt = (hi.tile == CMap::tile_tnt ? true : false);
					bool kudzu = isTileKudzu(hi.tile);
					if (ground || wood || dirt_stone || gold)
					{
						Vec2f tpos = map.getTileWorldPosition(hi.tileOffset) + Vec2f(4, 4);
						Vec2f offset = (tpos - blobPos);
						f32 tileangle = offset.Angle();
						f32 dif = Maths::Abs(exact_aimangle - tileangle);
						if (dif > 180)
							dif -= 360;
						if (dif < -180)
							dif += 360;

						dif = Maths::Abs(dif);
						//print("dif: "+dif);

						if (dif < 20.0f)
						{
							//detect corner

							int check_x = -(offset.x > 0 ? -1 : 1);
							int check_y = -(offset.y > 0 ? -1 : 1);
							if (map.isTileSolid(hi.hitpos - Vec2f(map.tilesize * check_x, 0)) &&
							        map.isTileSolid(hi.hitpos - Vec2f(0, map.tilesize * check_y)))
								continue;

							bool canhit = true; //default true if not jab
							if (jab) //fake damage
							{
								info.tileDestructionLimiter++;
								canhit = ((info.tileDestructionLimiter % ((wood || dirt_stone) ? 3 : 2)) == 0);
							}
							else //reset fake dmg for next time
							{
								info.tileDestructionLimiter = 0;
							}

							//dont dig through no build zones
							canhit = canhit && map.getSectorAtPosition(tpos, "no build") is null;

							dontHitMoreMap = true;
							if (canhit)
							{
								map.server_DestroyTile(hi.hitpos, 0.1f, this);
							}
						}
					}
					else if (glass || tnt || kudzu)
					{
						dontHitMoreMap = true;
						map.server_DestroyTile(hi.hitpos, 0.1f, this);
					}
				}
		}
	}

	// destroy grass

	if (((aimangle >= 0.0f && aimangle <= 180.0f) || damage > 1.0f) &&    // aiming down or slash
	        (deltaInt == DELTA_BEGIN_ATTACK + 1)) // hit only once
	{
		f32 tilesize = map.tilesize;
		int steps = Maths::Ceil(2 * radius / tilesize);
		int sign = this.isFacingLeft() ? -1 : 1;

		for (int y = 0; y < steps; y++)
			for (int x = 0; x < steps; x++)
			{
				Vec2f tilepos = blobPos + Vec2f(x * tilesize * sign, y * tilesize);
				TileType tile = map.getTile(tilepos).type;

				if (map.isTileGrass(tile))
				{
					map.server_DestroyTile(tilepos, damage, this);

					if (damage <= 1.0f)
					{
						return;
					}
				}
			}
	}
}

bool isSliding(KnightInfo@ knight)
{
	return (knight.slideTime > 0 && knight.slideTime < 45);
}

//a little push forward

void pushForward(CBlob@ this, f32 normalForce, f32 pushingForce, f32 verticalForce)
{
	f32 facing_sign = this.isFacingLeft() ? -1.0f : 1.0f ;
	bool pushing_in_facing_direction =
	    (facing_sign < 0.0f && this.isKeyPressed(key_left)) ||
	    (facing_sign > 0.0f && this.isKeyPressed(key_right));
	f32 force = normalForce;

	if (pushing_in_facing_direction)
	{
		force = pushingForce;
	}

	this.AddForce(Vec2f(force * facing_sign , verticalForce));
}

//bomb management

bool hasItem(CBlob@ this, const string &in name)
{
	CBitStream reqs, missing;
	AddRequirement(reqs, "blob", name, "Bombs", 1);
	CInventory@ inv = this.getInventory();

	if (inv !is null)
	{
		return hasRequirements(inv, reqs, missing);
	}
	else
	{
		warn("our inventory was null! KnightLogic.as");
	}

	return false;
}

void TakeItem(CBlob@ this, const string &in name)
{
	CBlob@ carried = this.getCarriedBlob();
	if (carried !is null)
	{
		if (carried.getName() == name)
		{
			carried.server_Die();
			return;
		}
	}

	CBitStream reqs, missing;
	AddRequirement(reqs, "blob", name, "Bombs", 1);
	CInventory@ inv = this.getInventory();

	if (inv !is null)
	{
		if (hasRequirements(inv, reqs, missing))
		{
			server_TakeRequirements(inv, reqs);
		}
		else
		{
			warn("took a bomb even though we dont have one! KnightLogic.as");
		}
	}
	else
	{
		warn("our inventory was null! KnightLogic.as");
	}
}

void onHitBlob(CBlob@ this, Vec2f worldPoint, Vec2f velocity, f32 damage, CBlob@ hitBlob, u8 customData)
{
	KnightInfo@ knight;
	if (!this.get("knightInfo", @knight))
	{
		return;
	}

	if (customData == Hitters::stab &&
	        ( //is a jab - note we dont have the dmg in here at the moment :/
	            knight.state == KnightStates::sword_cut_mid ||
	            knight.state == KnightStates::sword_cut_mid_down ||
	            knight.state == KnightStates::sword_cut_up ||
	            knight.state == KnightStates::sword_cut_down
	        )
	        && blockAttack(hitBlob, velocity, 0.0f))
	{
		this.getSprite().PlaySound("/Stun", 1.0f, this.getSexNum() == 0 ? 1.0f : 2.0f);
		SetKnocked(this, 30);
	}
}



// bomb pick menu

void onCreateInventoryMenu(CBlob@ this, CBlob@ forBlob, CGridMenu @gridmenu)
{
	if (bombTypeNames.length == 0)
	{
		return;
	}

	this.ClearGridMenusExceptInventory();
	Vec2f pos(gridmenu.getUpperLeftPosition().x + 0.5f * (gridmenu.getLowerRightPosition().x - gridmenu.getUpperLeftPosition().x),
	          gridmenu.getUpperLeftPosition().y - 32 * 1 - 2 * 24);
	CGridMenu@ menu = CreateGridMenu(pos, this, Vec2f(bombTypeNames.length, 2), "Current bomb");
	u8 weaponSel = this.get_u8("bomb type");

	if (menu !is null)
	{
		menu.deleteAfterClick = false;

		for (uint i = 0; i < bombTypeNames.length; i++)
		{
			string matname = bombTypeNames[i];
			CGridButton @button = menu.AddButton(bombIcons[i], bombNames[i], this.getCommandID("pick " + matname));

			if (button !is null)
			{
				bool enabled = this.getBlobCount(bombTypeNames[i]) > 0;
				button.SetEnabled(enabled);
				button.selectOneOnClick = true;
				if (weaponSel == i)
				{
					button.SetSelected(1);
				}
			}
		}
	}
}


void onAttach(CBlob@ this, CBlob@ attached, AttachmentPoint @attachedPoint)
{
	for (uint i = 0; i < bombTypeNames.length; i++)
	{
		if (attached.getName() == bombTypeNames[i])
		{
			this.set_u8("bomb type", i);
			break;
		}
	}
}

void onAddToInventory(CBlob@ this, CBlob@ blob)
{
	const string itemname = blob.getName();
	if (this.isMyPlayer() && this.getInventory().getItemsCount() > 1)
	{
		for (uint j = 1; j < bombTypeNames.length; j++)
		{
			if (itemname == bombTypeNames[j])
			{
				SetHelp(this, "help inventory", "knight", "$Help_Bomb1$$Swap$$Help_Bomb2$         $KEY_TAP$$KEY_F$", "", 2);
				break;
			}
		}
	}

	if (this.getInventory().getItemsCount() == 0 || itemname == "mat_bombs")
	{
		for (uint j = 0; j < bombTypeNames.length; j++)
		{
			if (itemname == bombTypeNames[j])
			{
				this.set_u8("bomb type", j);
				return;
			}
		}
	}
}

void SetFirstAvailableBomb(CBlob@ this)
{
	u8 type = 255;
	if (this.exists("bomb type"))
		type = this.get_u8("bomb type");

	CInventory@ inv = this.getInventory();

	bool typeReal = (uint(type) < bombTypeNames.length);
	if (typeReal && inv.getItem(bombTypeNames[type]) !is null)
		return;

	for (int i = 0; i < inv.getItemsCount(); i++)
	{
		const string itemname = inv.getItem(i).getName();
		for (uint j = 0; j < bombTypeNames.length; j++)
		{
			if (itemname == bombTypeNames[j])
			{
				type = j;
				break;
			}
		}

		if (type != 255)
			break;
	}

	this.set_u8("bomb type", type);
}

// Blame Fuzzle.
bool canHit(CBlob@ this, CBlob@ b)
{

	if (b.hasTag("invincible"))
		return false;

	// Don't hit temp blobs and items carried by teammates.
	if (b.isAttached())
	{

		CBlob@ carrier = b.getCarriedBlob();

		if (carrier !is null)
			if (carrier.hasTag("player")
			        && (this.getTeamNum() == carrier.getTeamNum() || b.hasTag("temp blob")))
				return false;

	}

	if (b.hasTag("dead"))
		return true;

	return b.getTeamNum() != this.getTeamNum();

}