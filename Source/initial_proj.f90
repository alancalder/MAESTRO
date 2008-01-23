module initial_proj_module

  implicit none

  private
  public :: initial_proj

contains

  subroutine initial_proj(nlevs,uold,sold,pres,gpres,Source_old,hgrhs, &
                          div_coeff_old,s0_old,p0_old,gam1,grav_cell,dx,the_bc_tower,mla)

    use variables, only: temp_comp, press_comp
    use network, only: nspec
    use define_bc_module
    use bl_constants_module
    use probin_module
    use geometry, only: spherical, nr
    use proj_parameters, only: initial_projection_comp
    use make_explicit_thermal_module
    use make_S_module
    use average_module
    use hgrhs_module
    use fill_3d_module
    use hgproject_module
    use multifab_module
    use ml_layout_module
    use heating_module

    integer        , intent(in   ) :: nlevs
    type(multifab) , intent(inout) :: uold(:)
    type(multifab) , intent(in   ) :: sold(:)
    type(multifab) , intent(inout) :: pres(:)
    type(multifab) , intent(inout) :: gpres(:)
    type(multifab) , intent(inout) :: Source_old(:)
    type(multifab) , intent(inout) :: hgrhs(:)
    real(kind=dp_t), intent(in   ) :: div_coeff_old(:,0:)
    real(kind=dp_t), intent(in   ) :: s0_old(:,0:,:)
    real(kind=dp_t), intent(in   ) :: p0_old(:,0:)
    real(kind=dp_t), intent(in   ) :: gam1(:,0:)
    real(kind=dp_t), intent(in   ) :: grav_cell(:,:)
    real(kind=dp_t), intent(in   ) :: dx(:,:)
    type(bc_tower) , intent(in   ) :: the_bc_tower
    type(ml_layout), intent(inout) :: mla

    ! local
    integer    :: n
    real(dp_t) :: dt_temp

    type(multifab) :: gamma1_term(nlevs)
    type(multifab) :: thermal(nlevs)
    type(multifab) :: rhohalf(nlevs)
    type(multifab) :: rho_omegadot1(nlevs)
    type(multifab) :: rho_Hext(nlevs)
    type(multifab) :: div_coeff_3d(nlevs)

    real(dp_t), allocatable :: Sbar(:,:,:)  

    allocate(Sbar(nlevs,nr(nlevs),1))

    if ( parallel_IOProcessor() ) then
       print *, 'DOING THE INITIAL VELOCITY PROJECTION'
       print *, ' '
    end if

    do n=1,nlevs
       call multifab_build(thermal(n), mla%la(n), 1, 1)
    end do
    
    if(use_thermal_diffusion) then
       call make_explicit_thermal(mla,dx,thermal,sold,p0_old, &
                                  the_bc_tower,temp_diffusion_formulation)
    else
       do n=1,nlevs
          call setval(thermal(n), ZERO, all=.true.)
       end do
    end if
    
    do n=1,nlevs
       call multifab_build(gamma1_term(n), mla%la(n), 1, 0)
       call multifab_build(rho_omegadot1(n), mla%la(n), nspec, 0)
       call multifab_build(rho_Hext(n),      mla%la(n), 1,     0)
       ! we don't have a legit timestep yet, so we set rho_omegadot1 and rho_Hext to 0 
       call setval(rho_omegadot1(n), ZERO, all=.true.)
       call setval(     rho_Hext(n), ZERO, all=.true.)
    end do

    call make_S(nlevs,Source_old,gamma1_term,sold,uold,rho_omegadot1,rho_Hext,thermal, &
                s0_old(:,:,temp_comp),p0_old,gam1,dx)
    do n=1,nlevs
       call destroy(thermal(n))
       call destroy(rho_omegadot1(n))
       call destroy(rho_Hext(n))
    end do
    
    call average(mla,Source_old,Sbar,dx,1,1)
    
    ! Note that we use rhohalf, filled with 1 at this point, as a temporary
    ! in order to do a constant-density initial projection.

    do n=1,nlevs
       call multifab_build(rhohalf(n), mla%la(n), 1, 1)
       call setval(rhohalf(n),ONE,1,1,all=.true.)
    end do
    
    call make_hgrhs(nlevs,hgrhs,Source_old,gamma1_term,Sbar(:,:,1),div_coeff_old,dx)

    do n=1,nlevs
       call destroy(gamma1_term(n))
    end do

    ! dt doesn't matter for the initial projection since we're throwing
    ! away the p and gpres anyway
    dt_temp = ONE

    if (spherical .eq. 1) then
       do n=1,nlevs
          call multifab_build(div_coeff_3d(n), mla%la(n), 1, 0)
       end do
       call fill_3d_data_wrapper(nlevs,div_coeff_3d,div_coeff_old,dx)
       call hgproject(initial_projection_comp,mla,uold,uold,rhohalf,pres,gpres,dx, &
                      dt_temp,the_bc_tower,press_comp, &
                      hgrhs,div_coeff_3d=div_coeff_3d,eps_in=1.d-10)
       
    else
       call hgproject(initial_projection_comp,mla,uold,uold,rhohalf,pres,gpres,dx, &
                      dt_temp,the_bc_tower,press_comp, &
                      hgrhs,div_coeff_1d=div_coeff_old)
    end if

    if(spherical .eq. 1) then
       do n=1,nlevs
          call destroy(div_coeff_3d(n))
       end do
    end if
    
    do n=1,nlevs
       call destroy(rhohalf(n))
    end do

    do n=1,nlevs
       call setval( pres(n), 0.0_dp_t, all=.true.)
       call setval(gpres(n), 0.0_dp_t, all=.true.)
    end do
    
    deallocate(Sbar)

  end subroutine initial_proj

end module initial_proj_module
