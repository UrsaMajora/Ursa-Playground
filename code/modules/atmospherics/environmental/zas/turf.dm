/turf
	var/needs_air_update = FALSE
/turf/simulated
	var/datum/zas_zone/zone
	var/open_directions
	/// Do we show gas overlays?
	var/allow_gas_overlays = TRUE

/turf/proc/update_air_properties()
	var/block = c_airblock(src)
	if(block & AIR_BLOCKED)
		//dbg(blocked)
		return 1

	#ifdef MULTIZAS
	for(var/d = 1, d < 64, d *= 2)
	#else
	for(var/d = 1, d < 16, d *= 2)
	#endif

		var/turf/unsim = get_step(src, d)

		if(!unsim)
			continue

		block = unsim.c_airblock(src)

		if(block & AIR_BLOCKED)
			//unsim.dbg(air_blocked, turn(180,d))
			continue

		var/r_block = c_airblock(unsim)

		if(r_block & AIR_BLOCKED)
			continue

		if(istype(unsim, /turf/simulated))

			var/turf/simulated/sim = unsim
			if(air_master.has_valid_zone(sim))

				air_master.connect(sim, src)

/*
	Simple heuristic for determining if removing the turf from it's zone will not partition the zone (A very bad thing).
	Instead of analyzing the entire zone, we only check the nearest 3x3 turfs surrounding the src turf.
	This implementation may produce false negatives but it (hopefully) will not produce any false postiives.
*/

/turf/simulated/proc/can_safely_remove_from_zone()
	if(!zone)
		return TRUE

	var/check_dirs = get_zone_neighbours(src)
	var/unconnected_dirs = check_dirs

	#ifdef MULTIZAS
	var/to_check = GLOB.cornerdirsz
	#else
	var/to_check = GLOB.cornerdirs
	#endif

	for(var/dir in to_check)
		//for each pair of "adjacent" cardinals (e.g. NORTH and WEST, but not NORTH and SOUTH)
		if((dir & check_dirs) == dir)
			//check that they are connected by the corner turf
			var/connected_dirs = get_zone_neighbours(get_step(src, dir))
			if(connected_dirs && (dir & GLOB.reverse_dir[connected_dirs]) == dir)
				unconnected_dirs &= ~dir //they are, so unflag the cardinals in question

	//it is safe to remove src from the zone if all cardinals are connected by corner turfs
	return !unconnected_dirs

//helper for can_safely_remove_from_zone()
/turf/simulated/proc/get_zone_neighbours(turf/simulated/T)
	. = 0
	if(istype(T) && T.zone)
		#ifdef MULTIZAS
		var/to_check = GLOB.cardinalz
		#else
		var/to_check = GLOB.cardinal
		#endif
		for(var/dir in to_check)
			var/turf/simulated/other = get_step(T, dir)
			if(istype(other) && other.zone == T.zone && !(other.c_airblock(T) & AIR_BLOCKED) && get_dist(src, other) <= 1)
				. |= dir

/turf/simulated/update_air_properties()
	if(zone && zone.invalid)
		c_copy_air()
		zone = null //Easier than iterating through the list at the zone.

	var/s_block = c_airblock(src)
	if(s_block & AIR_BLOCKED)
		#ifdef ZASDBG
		if(verbose) to_chat(world, "Self-blocked.")
		//dbg(blocked)
		#endif
		if(zone)
			var/datum/zas_zone/z = zone

			if(can_safely_remove_from_zone()) //Helps normal airlocks avoid rebuilding zones all the time
				z.remove(src)
			else
				z.rebuild()

		return 1

	var/previously_open = open_directions
	open_directions = 0

	var/list/postponed
	#ifdef MULTIZAS
	for(var/d = 1, d < 64, d *= 2)
	#else
	for(var/d = 1, d < 16, d *= 2)
	#endif

		var/turf/unsim = get_step(src, d)

		if(!unsim) //edge of map
			continue

		var/block = unsim.c_airblock(src)
		if(block & AIR_BLOCKED)

			#ifdef ZASDBG
			if(verbose) to_chat(world, "[d] is blocked.")
			//unsim.dbg(air_blocked, turn(180,d))
			#endif

			continue

		var/r_block = c_airblock(unsim)
		if(r_block & AIR_BLOCKED)

			#ifdef ZASDBG
			if(verbose) to_chat(world, "[d] is blocked.")
			//dbg(air_blocked, d)
			#endif

			//Check that our zone hasn't been cut off recently.
			//This happens when windows move or are constructed. We need to rebuild.
			if((previously_open & d) && istype(unsim, /turf/simulated))
				var/turf/simulated/sim = unsim
				if(zone && sim.zone == zone)
					zone.rebuild()
					return

			continue

		open_directions |= d

		if(istype(unsim, /turf/simulated))

			var/turf/simulated/sim = unsim
			sim.open_directions |= GLOB.reverse_dir[d]

			if(air_master.has_valid_zone(sim))

				//Might have assigned a zone, since this happens for each direction.
				if(!zone)

					//We do not merge if
					//    they are blocking us and we are not blocking them, or if
					//    we are blocking them and not blocking ourselves - this prevents tiny zones from forming on doorways.
					if(((block & ZONE_BLOCKED) && !(r_block & ZONE_BLOCKED)) || ((r_block & ZONE_BLOCKED) && !(s_block & ZONE_BLOCKED)))
						#ifdef ZASDBG
						if(verbose) to_chat(world, "[d] is zone blocked.")
						//dbg(zone_blocked, d)
						#endif

						//Postpone this tile rather than exit, since a connection can still be made.
						if(!postponed) postponed = list()
						postponed.Add(sim)

					else

						sim.zone.add(src)

						#ifdef ZASDBG
						dbg(assigned)
						if(verbose) to_chat(world, "Added to [zone]")
						#endif

				else if(sim.zone != zone)

					#ifdef ZASDBG
					if(verbose) to_chat(world, "Connecting to [sim.zone]")
					#endif

					air_master.connect(src, sim)


			#ifdef ZASDBG
				else if(verbose) to_chat(world, "[d] has same zone.")

			else if(verbose) to_chat(world, "[d] has invalid zone.")
			#endif

		else

			//Postponing connections to tiles until a zone is assured.
			if(!postponed) postponed = list()
			postponed.Add(unsim)

	if(!air_master.has_valid_zone(src)) //Still no zone, make a new one.
		var/datum/zas_zone/newzone = new
		newzone.add(src)

	#ifdef ZASDBG
		dbg(created)

	ASSERT(zone)
	#endif

	//At this point, a zone should have happened. If it hasn't, don't add more checks, fix the bug.

	for(var/turf/T in postponed)
		air_master.connect(src, T)

/turf/proc/post_update_air_properties()
	connections?.update_all()

/turf/proc/make_air()
	air = new /datum/gas_mixture
	air.copy_from_turf(src)
	air.group_multiplier = 1
	air.volume = CELL_VOLUME

/turf/simulated/proc/c_copy_air()
	if(!air)
		air = new /datum/gas_mixture
	air.copy_from(zone.air)
	air.group_multiplier = 1