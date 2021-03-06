!!  Create a 1-d hydrostatic, atmosphere with an isothermal region
!!  (T_star) representing the NS, a hyperbolic tangent rise to a
!!  peak temperature (T_base) representing the base of an accreted
!!  layer, an isoentropic profile down to a lower temperature (T_lo),
!!  and then isothermal. This can serve as an initial model for a
!!  nova or XRB.
!!
!!  The temperature profile is:
!!
!!         ^
!!         |
!!  T_base +        /\
!!         |       /  \
!!         |      /  . \
!!  T_star +-----+      \
!!         |     .   .   \
!!         |              \
!!         |     .   .     \
!!  T_lo   +                +-----------
!!         |     .   .
!!         +-----+---+---------------> r
!!         |      \  /
!!         |      delta
!!         |< H_star>|
!!
!!  We take dens_base, the density at the base of the isentropic layer
!!  as input.  The composition is "ash" in the lower isothermal region
!!  and "fuel" in the isentropic and upper isothermal regions.  In the
!!  linear transition region, we linearly interpolate the composition.
!!
!!  The fuel and ash compositions are specified by the fuel?_name,
!!  fuel?_frac and ash?_name, ash?_frac parameters (name of the species
!!  and mass fraction).  Where ? = 1,2,3.
!!
!!  The model is placed into HSE by the following differencing:
!!
!!   (1/dr) [ <P>_i - <P>_{i-1} ] = (1/2) [ <rho>_i + <rho>_{i-1} ] g
!!
!!  This will be iterated over in tandem with the EOS call,
!!  P(i-1) = P_eos(rho(i-1), T(i-1), X(i-1)
!!

program init_1d_tanh

  use bl_types
  use bl_constants_module
  use bl_error_module
  use eos_module, only: eos_input_rt, eos, eos_init
  use eos_type_module, only: eos_t
  !use extern_probin_module, only: use_eos_coulomb
  use network, only : nspec, network_species_index, spec_names, network_init
  use fundamental_constants_module, only: Gconst

  implicit none

  integer :: i, n

  character(len=128) :: params_file

  real (kind=dp_t) :: T_base, T_star, T_lo
  real (kind=dp_t) :: dens_base
  real (kind=dp_t) :: H_star, delta

  real (kind=dp_t) :: slope_T, slope_xn(nspec)

  real (kind=dp_t) :: pres_base, entropy_base
  real (kind=dp_t), DIMENSION(nspec) :: xn_base, xn_star

  real (kind=dp_t), allocatable :: xzn_hse(:), xznl_hse(:), xznr_hse(:)
  real (kind=dp_t), allocatable :: model_hse(:,:)

  real :: A, B

  integer ::nx

  integer :: lun1, lun2

  ! define convenient indices for the scalars
  integer, parameter :: nvar = 3 + nspec
  integer, parameter :: idens = 1, &
                        itemp = 2, &
                        ipres = 3, &
                        ispec = 4

  ! we'll get the composition from the network module
  ! we allow for 3 different species separately in the fuel and ash
  integer :: ifuel1, ifuel2, ifuel3, ifuel4, ifuel5, ifuel6, ifuel7
  integer :: iash1, iash2, iash3, iash4
  character (len=32) :: fuel1_name, fuel2_name, fuel3_name, fuel4_name
  character (len=32) :: fuel5_name, fuel6_name, fuel7_name
  character (len=32) ::  ash1_name,  ash2_name,  ash3_name, ash4_name
  real (kind=dp_t) :: fuel1_frac, fuel2_frac, fuel3_frac, fuel4_frac
  real (kind=dp_t) :: fuel5_frac, fuel6_frac, fuel7_frac
  real (kind=dp_t) ::  ash1_frac,  ash2_frac,  ash3_frac, ash4_frac
  logical :: species_defined

  real (kind=dp_t) :: xmin, xmax, dCoord

  real (kind=dp_t) :: dens_zone, temp_zone, pres_zone, entropy
  real (kind=dp_t) :: dpd, dpt, dsd, dst

  real (kind=dp_t) :: p_want, drho, dtemp, delx

  real (kind=dp_t) :: g_zone, g_const, M_enclosed
  logical :: do_invsq_grav

  real (kind=dp_t), parameter :: TOL = 1.e-10

  integer, parameter :: MAX_ITER = 250

  integer :: iter

  logical :: converged_hse, fluff

  real (kind=dp_t), dimension(nspec) :: xn

  real (kind=dp_t) :: low_density_cutoff, smallx

  integer :: index_base

  logical :: isentropic

  character (len=256) :: outfile, outfile2
  character (len=8) :: num
  character (len=32) :: deltastr, dxstr
  character (len=32) :: num_to_unitstring

  real (kind=dp_t) :: max_hse_error, dpdr, rhog

  character (len=128) :: model_prefix

  integer :: narg

  logical :: index_base_from_temp

  type (eos_t) :: eos_state

  namelist /params/ nx, dens_base, T_star, T_base, T_lo, H_star, delta, &
                    fuel1_name, fuel2_name, fuel3_name, fuel4_name, &
                    fuel5_name, fuel6_name, fuel7_name, &
                    ash1_name, ash2_name, ash3_name, ash4_name, &
                    fuel1_frac, fuel2_frac, fuel3_frac, fuel4_frac, &
                    fuel5_frac, fuel6_frac, fuel7_frac, &
                    ash1_frac, ash2_frac, ash3_frac, ash4_frac, &
                    xmin, xmax, g_const, do_invsq_grav, M_enclosed, &
                    low_density_cutoff, model_prefix, index_base_from_temp

  ! determine if we specified a runtime parameters file or use the default
  narg = command_argument_count()

  if (narg == 0) then
     params_file = "_params"
  else
     call get_command_argument(1, value = params_file)
  endif




  ! define defaults for the parameters for this model
  nx = 640

  dens_base = 2.d6

  T_star = 1.d8
  T_base = 5.d8
  T_lo   = 5.e7

  H_star = 500.d0
  delta  = 25.d0

  fuel1_name = "helium-4"
  fuel2_name = ""
  fuel3_name = ""
  fuel4_name = ""
  fuel5_name = ""
  fuel6_name = ""
  fuel7_name = ""

  ash1_name  = "iron-56"
  ash2_name  = ""
  ash3_name  = ""
  ash4_name  = ""

  fuel1_frac = ONE
  fuel2_frac = ZERO
  fuel3_frac = ZERO
  fuel4_frac = ZERO
  fuel5_frac = ZERO
  fuel6_frac = ZERO
  fuel7_frac = ZERO

  ash1_frac = ONE
  ash2_frac = ZERO
  ash3_frac = ZERO
  ash4_frac = ZERO

  xmin = 0.0_dp_t
  xmax = 2.e3_dp_t

  model_prefix = "model"

  index_base_from_temp = .false.

  ! if do_invsq_grav = .false. we will use g_const for the
  ! gravitational acceleration.  Otherwise, we will compute gravity
  ! from M_enclosed and the distance from the origin
  M_enclosed = 2.d33
  g_const = -2.450d14
  do_invsq_grav = .false.

  low_density_cutoff = 1.d-4

  smallx = 1.d-10


  ! this comes in via extern_probin_module -- override the default
  ! here if we want
  !use_eos_coulomb = .true.


  ! initialize the EOS and network
  call eos_init()
  call network_init()

  ! check the namelist for any changed parameters
  open(unit=11, file=params_file, status="old", action="read")
  read(unit=11, nml=params)
  close(unit=11)


  ! get the species indices
  species_defined = .true.
  ifuel1 = network_species_index(trim(fuel1_name))
  if (ifuel1 < 0) species_defined = .false.

  if (fuel2_name /= "") then
     ifuel2 = network_species_index(trim(fuel2_name))
     if (ifuel2 < 0) species_defined = .false.
  endif

  if (fuel3_name /= "") then
     ifuel3 = network_species_index(trim(fuel3_name))
     if (ifuel3 < 0) species_defined = .false.
  endif

  if (fuel4_name /= "") then
     ifuel4 = network_species_index(trim(fuel4_name))
     if (ifuel4 < 0) species_defined = .false.
  endif

  if (fuel5_name /= "") then
     ifuel5 = network_species_index(trim(fuel5_name))
     if (ifuel5 < 0) species_defined = .false.
  endif

  if (fuel6_name /= "") then
     ifuel6 = network_species_index(trim(fuel6_name))
     if (ifuel6 < 0) species_defined = .false.
  endif

  if (fuel7_name /= "") then
     ifuel7 = network_species_index(trim(fuel7_name))
     if (ifuel7 < 0) species_defined = .false.
  endif


  iash1 = network_species_index(trim(ash1_name))
  if (iash1 < 0) species_defined = .false.

  if (ash2_name /= "") then
     iash2 = network_species_index(trim(ash2_name))
     if (iash2 < 0) species_defined = .false.
  endif

  if (ash3_name /= "") then
     iash3 = network_species_index(trim(ash3_name))
     if (iash3 < 0) species_defined = .false.
  endif

  if (ash4_name /= "") then
     iash4 = network_species_index(trim(ash4_name))
     if (iash4 < 0) species_defined = .false.
  endif

  if (.not. species_defined) then
     print *, ifuel1, ifuel2, ifuel3, ifuel4, ifuel5, ifuel6, ifuel7
     print *, iash1, iash2, iash3, iash4
     call bl_error("ERROR: species not defined")
  endif



  ! set the composition of the underlying star
  xn_star(:) = smallx
  xn_star(iash1) = ash1_frac
  if (ash2_name /= "") xn_star(iash2) = ash2_frac
  if (ash3_name /= "") xn_star(iash3) = ash3_frac
  if (ash4_name /= "") xn_star(iash4) = ash4_frac

  ! and the composition of the accreted layer
  xn_base(:) = smallx
  xn_base(ifuel1) = fuel1_frac
  if (fuel2_name /= "") xn_base(ifuel2) = fuel2_frac
  if (fuel3_name /= "") xn_base(ifuel3) = fuel3_frac
  if (fuel4_name /= "") xn_base(ifuel4) = fuel4_frac
  if (fuel5_name /= "") xn_base(ifuel5) = fuel5_frac
  if (fuel6_name /= "") xn_base(ifuel6) = fuel6_frac
  if (fuel7_name /= "") xn_base(ifuel7) = fuel7_frac

  ! check if they sum to 1
  if (abs(sum(xn_star) - ONE) > nspec*smallx) then
     call bl_error("ERROR: ash mass fractions don't sum to 1")
  endif

  if (abs(sum(xn_base) - ONE) > nspec*smallx) then
     call bl_error("ERROR: fuel mass fractions don't sum to 1")
  endif



!-----------------------------------------------------------------------------
! Create a 1-d uniform grid that is identical to the mesh that we are
! mapping onto, and then we want to force it into HSE on that mesh.
!-----------------------------------------------------------------------------

  ! allocate storage
  allocate(xzn_hse(nx))
  allocate(xznl_hse(nx))
  allocate(xznr_hse(nx))
  allocate(model_hse(nx,nvar))


  ! compute the coordinates of the new gridded function
  dCoord = (xmax - xmin) / dble(nx)

  do i = 1, nx
     xznl_hse(i) = xmin + (dble(i) - ONE)*dCoord
     xzn_hse(i)  = xmin + (dble(i) - HALF)*dCoord
     xznr_hse(i) = xmin + (dble(i))*dCoord
  enddo


  ! find the index of the base height
  index_base = -1
  do i = 1, nx
     if (xzn_hse(i) >= xmin + H_star + delta) then
        index_base = i+1
        exit
     endif
  enddo

  if (index_base == -1) then
     print *, 'ERROR: base_height not found on grid'
     call bl_error('ERROR: invalid base_height')
  endif


!-----------------------------------------------------------------------------
! put the model onto our new uniform grid
!-----------------------------------------------------------------------------

  fluff = .false.

  ! determine the conditions at the base
  eos_state%T     = T_base
  eos_state%rho   = dens_base
  eos_state%xn(:) = xn_base(:)

  call eos(eos_input_rt, eos_state)

  ! store the conditions at the base -- we'll use the entropy later
  ! to constrain the isentropic layer
  pres_base = eos_state%p
  entropy_base = eos_state%s

  print *, 'entropy_base = ', entropy_base
  print *, 'pres_base = ', pres_base

  ! set an initial temperature profile and composition
  do i = 1, nx

     !hyperbolic tangent transition:
     model_hse(i,ispec:ispec-1+nspec) = xn_star(1:nspec) + &
          HALF*(xn_base(1:nspec) - xn_star(1:nspec))* &
          (ONE + tanh((xzn_hse(i) - (xmin + H_star - delta) + delta)/delta))

     model_hse(i,itemp) = T_star + HALF*(T_base - T_star)* &
          (ONE + tanh((xzn_hse(i) - (xmin + H_star - delta) + delta)/delta))


     ! the density and pressure will be determined via HSE,
     ! for now, set them to the base conditions
     model_hse(i,idens) = dens_base
     model_hse(i,ipres) = pres_base

  enddo


  if (index_base_from_temp) then
     ! find the index of the base height -- look at the temperature for this
     index_base = -1
     do i = 1, nx
        !if (xzn_hse(i) >= xmin + H_star + delta) then
        if (model_hse(i,itemp) > 0.9995*T_base) then
           index_base = i+1
           exit
        endif
     enddo

     if (index_base == -1) then
        print *, 'ERROR: base_height not found on grid'
        call bl_error('ERROR: invalid base_height')
     endif
  endif

  print *, 'index_base = ', index_base

  ! make the base thermodynamics consistent for this base point -- that is
  ! what we will integrate from!
  eos_state%rho = model_hse(index_base,idens)
  eos_state%T = model_hse(index_base,itemp)
  eos_state%xn(:) = model_hse(index_base,ispec:ispec-1+nspec)

  call eos(eos_input_rt, eos_state)

  model_hse(index_base,ipres) = eos_state%p


!-----------------------------------------------------------------------------
! HSE + entropy solve
!-----------------------------------------------------------------------------

! the HSE state will be done putting creating an isentropic state until
! the temperature goes below T_lo -- then we will do isothermal.
! also, once the density goes below low_density_cutoff, we stop HSE

  isentropic = .true.

  !---------------------------------------------------------------------------
  ! integrate up
  !---------------------------------------------------------------------------
  do i = index_base+1, nx

     delx = xzn_hse(i) - xzn_hse(i-1)

     ! compute the gravitation acceleration at the lower edge
     if (do_invsq_grav) then
        g_zone = -Gconst*M_enclosed/xznl_hse(i)**2
     else
        g_zone = g_const
     endif

     ! we've already set initial guesses for density, temperature, and
     ! composition
     dens_zone = model_hse(i,idens)
     temp_zone = model_hse(i,itemp)
     xn(:) = model_hse(i,ispec:nvar)


     !-----------------------------------------------------------------------
     ! iteration loop
     !-----------------------------------------------------------------------

     ! start off the Newton loop by saying that the zone has not converged
     converged_hse = .FALSE.

     if (.not. fluff) then

        do iter = 1, MAX_ITER

           if (isentropic) then

              ! get the pressure we want from the HSE equation, just the
              ! zone below the current.  Note, we are using an average of
              ! the density of the two zones as an approximation of the
              ! interface value -- this means that we need to iterate for
              ! find the density and pressure that are consistent

              ! furthermore, we need to get the entropy that we need,
              ! which will come from adjusting the temperature in
              ! addition to the density.

              ! HSE differencing
              p_want = model_hse(i-1,ipres) + &
                   delx*0.5*(dens_zone + model_hse(i-1,idens))*g_zone



              ! now we have two functions to zero:
              !   A = p_want - p(rho,T)
              !   B = entropy_base - s(rho,T)
              ! We use a two dimensional Taylor expansion and find the deltas
              ! for both density and temperature


              ! now we know the pressure and the entropy that we want, so we
              ! need to find the temperature and density through a two
              ! dimensional root find

              ! (t, rho) -> (p, s)
              eos_state%T     = temp_zone
              eos_state%rho   = dens_zone
              eos_state%xn(:) = xn(:)

              call eos(eos_input_rt, eos_state)

              entropy = eos_state%s
              pres_zone = eos_state%p

              dpt = eos_state%dpdt
              dpd = eos_state%dpdr
              dst = eos_state%dsdt
              dsd = eos_state%dsdr

              A = p_want - pres_zone
              B = entropy_base - entropy

              dtemp = ((dsd/(dpd-0.5*delx*g_zone))*A - B)/ &
                   (dsd*dpt/(dpd -0.5*delx*g_zone) - dst)

              drho = (A - dpt*dtemp)/(dpd - 0.5*delx*g_zone)

              dens_zone = max(0.9_dp_t*dens_zone, &
                   min(dens_zone + drho, 1.1_dp_t*dens_zone))

              temp_zone = max(0.9_dp_t*temp_zone, &
                   min(temp_zone + dtemp, 1.1_dp_t*temp_zone))


              ! check if the density falls below our minimum cut-off --
              ! if so, floor it
              if (dens_zone < low_density_cutoff) then

                 dens_zone = low_density_cutoff
                 temp_zone = T_lo
                 converged_hse = .TRUE.
                 fluff = .TRUE.
                 exit

              endif

              ! if (A < TOL .and. B < ETOL) then
              if (abs(drho) < TOL*dens_zone .and. &
                  abs(dtemp) < TOL*temp_zone) then
                 converged_hse = .TRUE.
                 exit
              endif

           else

              ! do isothermal
              p_want = model_hse(i-1,ipres) + &
                   delx*0.5*(dens_zone + model_hse(i-1,idens))*g_zone

              temp_zone = T_lo

              ! (t, rho) -> (p)
              eos_state%T   = temp_zone
              eos_state%rho = dens_zone
              eos_state%xn(:) = xn(:)

              call eos(eos_input_rt, eos_state)

              entropy = eos_state%s
              pres_zone = eos_state%p

              dpd = eos_state%dpdr

              drho = (p_want - pres_zone)/(dpd - 0.5*delx*g_zone)

              dens_zone = max(0.9*dens_zone, &
                   min(dens_zone + drho, 1.1*dens_zone))

              if (abs(drho) < TOL*dens_zone) then
                 converged_hse = .TRUE.
                 exit
              endif

              if (dens_zone < low_density_cutoff) then

                 dens_zone = low_density_cutoff
                 temp_zone = T_lo
                 converged_hse = .TRUE.
                 fluff = .TRUE.
                 exit

              endif

           endif

           if (temp_zone < T_lo) then
              temp_zone = T_lo
              isentropic = .false.
           endif

        enddo


        if (.NOT. converged_hse) then

           print *, 'Error zone', i, ' did not converge in init_1d'
           print *, 'integrate up'
           print *, dens_zone, temp_zone
           print *, p_want, entropy_base, entropy
           print *, drho, dtemp
           call bl_error('Error: HSE non-convergence')

        endif

     else
        dens_zone = low_density_cutoff
        temp_zone = T_lo
     endif


     ! call the EOS one more time for this zone and then go on to the next
     ! (t, rho) -> (p)
     eos_state%T     = temp_zone
     eos_state%rho   = dens_zone
     eos_state%xn(:) = xn(:)

     call eos(eos_input_rt, eos_state)

     pres_zone = eos_state%p

     ! update the thermodynamics in this zone
     model_hse(i,idens) = dens_zone
     model_hse(i,itemp) = temp_zone
     model_hse(i,ipres) = pres_zone


     ! to make this process converge faster, set the density in the
     ! next zone to the density in this zone
     ! model_hse(i+1,idens) = dens_zone

  enddo


  !---------------------------------------------------------------------------
  ! integrate down -- using the temperature profile defined above
  !---------------------------------------------------------------------------
  do i = index_base-1, 1, -1

     delx = xzn_hse(i+1) - xzn_hse(i)

     ! compute the gravitation acceleration at the upper edge
     if (do_invsq_grav) then
        g_zone = -Gconst*M_enclosed/xznr_hse(i)**2
     else
        g_zone = g_const
     endif

     ! we already set the temperature and composition profiles
     temp_zone = model_hse(i,itemp)
     xn(:) = model_hse(i,ispec:nvar)

     ! use our previous initial guess for density
     dens_zone = model_hse(i+1,idens)


     !-----------------------------------------------------------------------
     ! iteration loop
     !-----------------------------------------------------------------------

     ! start off the Newton loop by saying that the zone has not converged
     converged_hse = .FALSE.

     do iter = 1, MAX_ITER

        ! get the pressure we want from the HSE equation, just the
        ! zone below the current.  Note, we are using an average of
        ! the density of the two zones as an approximation of the
        ! interface value -- this means that we need to iterate for
        ! find the density and pressure that are consistent

        ! HSE differencing
        p_want = model_hse(i+1,ipres) - &
             delx*0.5*(dens_zone + model_hse(i+1,idens))*g_zone


        ! we will take the temperature already defined in model_hse
        ! so we only need to zero:
        !   A = p_want - p(rho)

        ! (t, rho) -> (p)
        eos_state%T     = temp_zone
        eos_state%rho   = dens_zone
        eos_state%xn(:) = xn(:)

        call eos(eos_input_rt, eos_state)

        pres_zone = eos_state%p

        dpd = eos_state%dpdr

        A = p_want - pres_zone

        drho = A/(dpd + 0.5*delx*g_zone)

        dens_zone = max(0.9_dp_t*dens_zone, &
             min(dens_zone + drho, 1.1_dp_t*dens_zone))


        if (abs(drho) < TOL*dens_zone) then
           converged_hse = .TRUE.
           exit
        endif

     enddo

     if (.NOT. converged_hse) then

        print *, 'Error zone', i, ' did not converge in init_1d'
        print *, 'integrate down'
        print *, dens_zone, temp_zone
        print *, p_want
        print *, drho
        call bl_error('Error: HSE non-convergence')

     endif


     ! call the EOS one more time for this zone and then go on to the next
     ! (t, rho) -> (p)
     eos_state%T     = temp_zone
     eos_state%rho   = dens_zone
     eos_state%xn(:) = xn(:)

     call eos(eos_input_rt, eos_state)

     pres_zone = eos_state%p

     ! update the thermodynamics in this zone
     model_hse(i,idens) = dens_zone
     model_hse(i,itemp) = temp_zone
     model_hse(i,ipres) = pres_zone

  enddo

  write(num,'(i8)') nx

  deltastr = num_to_unitstring(delta)
  dxstr = num_to_unitstring(dCoord)

  outfile = trim(model_prefix) // ".hse." // "tanh.delta_" // trim(adjustl(deltastr)) // ".dx_" // trim(adjustl(dxstr))
  outfile2 = trim(outfile) // ".extras"

  open (newunit=lun1, file=outfile, status="unknown")
  open (newunit=lun2, file=outfile2, status="unknown")

  write (lun1,1001) "# npts = ", nx
  write (lun1,1001) "# num of variables = ", nvar
  write (lun1,1002) "# density"
  write (lun1,1002) "# temperature"
  write (lun1,1002) "# pressure"

  do n = 1, nspec
     write (lun1, 1003) "# ", spec_names(n)
  enddo

1000 format (1x, 100(g26.16, 1x))
1001 format (a, i5)
1002 format (a)
1003 format (a,a)

  do i = 1, nx

     write (lun1,1000) xzn_hse(i), model_hse(i,idens), model_hse(i,itemp), model_hse(i,ipres), &
          (model_hse(i,ispec-1+n), n=1,nspec)

  enddo

  ! some metadata
  write (lun1, 1002) "# generated by toy_atm"
  write (lun1, 1003) "# inputs file", params_file


  write (lun2,1001), "# npts = ", nx
  write (lun2,1001), "# num of variables = ", 2
  write (lun2,1002), "# entropy"
  write (lun2,1002), "# c_s"

  ! test: bulk EOS call -- Maestro will do this once we are mapped, so make
  ! sure that we are in HSE with updated thermodynamics
  do i = 1, nx
     eos_state%rho = model_hse(i,idens)
     eos_state%T = model_hse(i,itemp)
     eos_state%xn(:) = model_hse(i,ispec:ispec-1+nspec)

     call eos(eos_input_rt, eos_state)

     model_hse(i,ipres) = eos_state%p

     write (lun2,1000), xzn_hse(i), eos_state%s, eos_state%cs
  enddo

  ! compute the maximum HSE error
  max_hse_error = -1.d30

  do i = 2, nx-1

     ! compute the gravitation acceleration at the lower edge
     if (do_invsq_grav) then
        g_zone = -Gconst*M_enclosed/xznl_hse(i)**2
     else
        g_zone = g_const
     endif

     dpdr = (model_hse(i,ipres) - model_hse(i-1,ipres))/delx
     rhog = HALF*(model_hse(i,idens) + model_hse(i-1,idens))*g_zone

     if (dpdr /= ZERO .and. model_hse(i+1,idens) > low_density_cutoff) then
        max_hse_error = max(max_hse_error, abs(dpdr - rhog)/abs(dpdr))
     endif

  enddo

  print *, 'maximum HSE error = ', max_hse_error
  print *, ' '

  close (unit=lun1)
  close (unit=lun2)

end program init_1d_tanh


function num_to_unitstring(value)

  use bl_types
  implicit none

  real (kind=dp_t) :: value
  character (len=32) :: num_to_unitstring
  character (len=16) :: temp

  if (value > 1.d5) then

     ! work in km
     write(temp,'(f6.3)') value/1.d5
     num_to_unitstring = trim(temp) // "km"
  else

     ! work in cm
     if (value > 1.d3) then
        write(temp,'(f8.3)') value
        num_to_unitstring = trim(temp) // "cm"

     else
        write(temp,'(f6.3)') value
        num_to_unitstring = trim(temp) // "cm"
     endif

  endif

  return
end function num_to_unitstring
