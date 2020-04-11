/*
	get_holder_at_turf_level(): Similar to get_turf(), will return the "highest up" holder of this atom, excluding the turf.
	Example: A fork inside a box inside a locker will return the locker. Essentially, get_just_before_turf().
*/ //Credit to /vg/
/proc/get_holder_at_turf_level(const/atom/movable/O)
	if(!istype(O)) //atom/movable does not include areas
		return
	var/atom/A
	for(A=O, A && !isturf(A.loc), A=A.loc);  // semicolon is for the empty statement
	return A

/proc/get_safe_ventcrawl_target(var/obj/machinery/atmospherics/unary/vent_pump/start_vent)
	if(!start_vent.network || !start_vent.network.normal_members.len)
		return
	var/list/vent_list = list()
	for(var/obj/machinery/atmospherics/unary/vent_pump/vent in start_vent.network.normal_members)
		if(vent == start_vent)
			continue
		if(vent.welded)
			continue
		if(istype(get_area(vent), /area/crew_quarters/sleep)) //No going to dorms
			continue
		vent_list += vent
	if(!vent_list.len)
		return
	return pick(vent_list)

/proc/split_into_3(var/total)
	if(!total || !isnum(total))
		return

	var/part1 = rand(0,total)
	var/part2 = rand(0,total)
	var/part3 = total-(part1+part2)

	if(part3<0)
		part1 = total-part1
		part2 = total-part2
		part3 = -part3

	return list(part1, part2, part3)

//Sender is optional
/proc/admin_chat_message(var/message = "Debug Message", var/color = "#FFFFFF", var/sender)
	if(message)	//CITADEL CHANGE - adds TGS3 integration to those fancy verbose round event messages
		world.TgsTargetedChatBroadcast(message, TRUE)	//CITADEL CHANGE - ditto
	if (!config_legacy.chat_webhook_url || !message)
		return
	spawn(0)
		var/query_string = "type=adminalert"
		query_string += "&key=[url_encode(config_legacy.chat_webhook_key)]"
		query_string += "&msg=[url_encode(message)]"
		query_string += "&color=[url_encode(color)]"
		if(sender)
			query_string += "&from=[url_encode(sender)]"
		world.Export("[config_legacy.chat_webhook_url]?[query_string]")
