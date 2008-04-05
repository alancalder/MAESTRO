module base_io_module

  use bl_types

  implicit none

  private

  public :: write_base_state, read_base_state

contains

  subroutine write_base_state(nlevs,state_name,w0_name,etarho_name,chk_name, &
                              rho0,rhoh0,p0,gamma1bar,w0,etarho,div_coeff,psi,problo)
    
    use parallel
    use bl_prof_module
    use geometry, only : dr, nr
    use network, only: nspec
    use variables, only: rho_comp, rhoh_comp
    use bl_constants_module

    integer          , intent(in) :: nlevs
    character(len=11), intent(in) :: state_name
    character(len=8) , intent(in) :: w0_name
    character(len=9) , intent(in) :: etarho_name
    character(len=8) , intent(in) :: chk_name
    real(kind=dp_t)  , intent(in) :: rho0(:,:),rhoh0(:,:)
    real(kind=dp_t)  , intent(in) :: p0(:,:),gamma1bar(:,:)
    real(kind=dp_t)  , intent(in) :: div_coeff(:,:), psi(:,:)
    real(kind=dp_t)  , intent(in) :: w0(:,:),etarho(:,:)

    real(kind=dp_t) :: base_r, problo
    character(len=20) :: out_name
    integer :: i, n

    type(bl_prof_timer), save :: bpt

    call build(bpt, "write_base_state")

    if (parallel_IOProcessor()) then

       print*,"chk_name",chk_name
       print*,"state_name",state_name

       ! write out the base state quantities
       out_name = chk_name // "/" // state_name
       write(6,*) 'Writing base state to ',out_name

       open(unit=99,file=out_name,form = "formatted", access = "sequential",action="write")

       do n=1,nlevs
          do i=1,nr(n)
             base_r = problo + (dble(i)-HALF) * dr(n)
             write(99,1000)  base_r, rho0(n,i), p0(n,i), gamma1bar(n,i), &
                  rhoh0(n,i), div_coeff(n,i), psi(n,i)
          end do
       end do
       close(99)

       ! write out w0 (it is edge-based, so it gets a separate file)
       out_name = chk_name // "/" // w0_name
       write(6,*) 'Writing w0 state to ',out_name
       write(6,*) ''

       open(unit=99,file=out_name,form = "formatted", access = "sequential",action="write")
       do n=1,nlevs
          do i=1,nr(n)+1
             base_r = problo + (dble(i)-1) * dr(n)
             write(99,1000)  base_r,w0(n,i)
          end do
       end do
       close(99)

       ! write out etarho (it is edge-based, so it gets a separate file)
       out_name = chk_name // "/" // etarho_name
       write(6,*) 'Writing etarho on edges to ',out_name
       write(6,*) ''

       open(unit=99,file=out_name,form = "formatted", access = "sequential",action="write")
       do n=1,nlevs
          do i=1,nr(n)+1
             base_r = problo + (dble(i)-1) * dr(n)
             write(99,1000)  base_r,etarho(n,i)
          end do
       end do
       close(99)

    endif

    call destroy(bpt)

1000 format(32(e30.20,1x))

  end subroutine write_base_state


  subroutine read_base_state(nlevs,state_name,w0_name,etarho_name,chk_name, &
                             rho0,rhoh0,p0,gamma1bar,w0,etarho,div_coeff,psi)

    use parallel
    use bl_prof_module
    use variables, only: rho_comp, rhoh_comp
    use network, only: nspec
    use geometry, only : dr, nr
    use bl_constants_module
    
    integer          , intent(in   ) :: nlevs
    character(len=11), intent(in   ) :: state_name
    character(len=8) , intent(in   ) :: w0_name
    character(len=9) , intent(in   ) :: etarho_name
    character(len=8) , intent(in   ) :: chk_name    
    real(kind=dp_t)  , intent(inout) :: rho0(:,:),rhoh0(:,:)
    real(kind=dp_t)  , intent(inout) :: p0(:,:),gamma1bar(:,:)
    real(kind=dp_t)  , intent(inout) :: div_coeff(:,:), psi(:,:)
    real(kind=dp_t)  , intent(inout) :: w0(:,:),etarho(:,:)
    real(kind=dp_t)  , allocatable   :: base_r(:,:)

    real(kind=dp_t) :: r_dummy
    character(len=20) :: out_name
    integer :: i, n

    type(bl_prof_timer), save :: bpt

    call build(bpt, "read_base_state")

    allocate(base_r(nlevs,nr(nlevs)))

    ! read in the state variables
    out_name = chk_name // "/" // state_name
    if (parallel_IOProcessor()) then
      print *,'Reading base state from ',out_name
    end if

    open(unit=99,file=out_name)

    do n=1,nlevs
       do i=1,nr(n)
          read(99,*)  base_r(n,i), rho0(n,i), p0(n,i), gamma1bar(n,i), &
               rhoh0(n,i), div_coeff(n,i), psi(n,i)
       end do
    end do
    close(99)

    ! read in w0
    out_name = chk_name // "/" // w0_name
    if (parallel_IOProcessor()) then
      print *,'Reading w0 state from ',out_name
    end if

    open(unit=99,file=out_name)
    do n=1,nlevs
       do i=1,nr(n)+1
          read(99,*)  r_dummy, w0(n,i)
       end do
    end do
    close(99)

    ! read in etarho
    out_name = chk_name // "/" // etarho_name
    if (parallel_IOProcessor()) then
      print *,'Reading etarho state from ',out_name
    end if

    open(unit=99,file=out_name)
    do n=1,nlevs
       do i=1,nr(n)+1
          read(99,*)  r_dummy, etarho(n,i)
       end do
    end do
    close(99)

    deallocate(base_r)

    call destroy(bpt)

  end subroutine read_base_state

end module base_io_module

