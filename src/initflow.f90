module mod_initflow
  use mpi
  use mod_common_mpi, only: myid,ierr
  use mod_param     , only: pi
  use mod_types
  implicit none
  private
  public initflow
  contains
  subroutine initflow(inivel,is_wallturb,lo,hi,ng,l,uref,lref,visc,bforce, &
                      xc,xf,yc,yf,zc,zf,dxc,dxf,dyc,dyf,dzc,dzf,u,v,w,p)
    !
    ! computes initial conditions for the velocity field
    !
    implicit none
    character(len=3), intent(in) :: inivel
    logical , intent(in) :: is_wallturb
    integer , intent(in), dimension(3) :: lo,hi,ng
    real(rp), intent(in), dimension(3) :: l
    real(rp), intent(inout) :: uref
    real(rp), intent(in) :: lref,visc,bforce
    real(rp), intent(in), dimension(lo(1)-1:) :: xc,xf,dxc,dxf
    real(rp), intent(in), dimension(lo(2)-1:) :: yc,yf,dyc,dyf
    real(rp), intent(in), dimension(lo(3)-1:) :: zc,zf,dzc,dzf
    real(rp), dimension(lo(1)-1:,lo(2)-1:,lo(3)-1:), intent(out) :: u,v,w,p
    real(rp), allocatable, dimension(:) :: u1d
    integer  :: i,j,k
    logical  :: is_noise,is_mean,is_pair
    real(rp) :: reb,retau
    real(rp) :: xcl,xfl,ycl,yfl,zcl,zfl
    !
    allocate(u1d(lo(3):hi(3)))
    is_noise = .false.
    is_mean  = .false.
    is_pair  = .false.
    select case(trim(inivel))
    case('cou')
      call couette(lo(3),hi(3),zc,l(3),uref,u1d)
    case('poi')
      call poiseuille(lo(3),hi(3),zc,l(3),uref,u1d)
      is_mean=.true.
    case('zer')
      u1d(:) = 0._rp
    case('log')
      call log_profile(lo(3),hi(3),zc,l(3),uref,lref,visc,u1d)
      is_noise = .true.
      is_mean = .true.
    case('hcp')
      call poiseuille(lo(3),hi(3),zc,2.*l(3),uref,u1d)
      is_mean = .true.
    case('hcl')
      call log_profile(lo(3),hi(3),zc,2.*l(3),uref,lref,visc,u1d)
      is_noise = .true.
      is_mean=.true.
    case('tgv')
      do k=lo(3),hi(3)
        zcl = zc(k)/l(3)*2._rp*pi
        do j=lo(2),hi(2)
          ycl = yc(j)/l(2)*2._rp*pi
          yfl = yf(j)/l(2)*2._rp*pi
          do i=lo(1),hi(1)
            xcl = xc(i)/l(1)*2._rp*pi
            xfl = xf(i)/l(1)*2._rp*pi
            u(i,j,k) =  sin(xfl)*cos(ycl)*cos(zcl)
            v(i,j,k) = -cos(xcl)*sin(yfl)*cos(zcl)
            w(i,j,k) = 0._rp
            p(i,j,k) = 0._rp!(cos(2._rp*xc)+cos(2._rp*yc))*(cos(2._rp*zc)+2._rp)/16._rp
          enddo
        enddo
      enddo
    case('pdc')
      if(is_wallturb) then ! turbulent flow
        retau  = sqrt(bforce*lref)*uref/visc
        reb    = (retau/.09_rp)**(1._rp/.88_rp)
        uref   = (reb/2._rp)/retau
      else                 ! laminar flow
        uref = (bforce*lref**2/(3._rp*visc))
      endif
      call poiseuille(lo(3),hi(3),zc,l(3),uref,u1d)
      is_mean=.true.
    case default
      if(myid.eq.0) write(stderr,*) 'ERROR: invalid name for initial velocity field'
      if(myid.eq.0) write(stderr,*) ''
      if(myid.eq.0) write(stderr,*) '*** Simulation abortited due to errors in the case file ***'
      if(myid.eq.0) write(stderr,*) '    check INFO_INPUT.md'
      call MPI_FINALIZE(ierr)
      error stop
    end select
    if(inivel.ne.'tgv') then
      do k=lo(3),hi(3)
        do j=lo(2),hi(2)
          do i=lo(1),hi(1)
            u(i,j,k) = u1d(k)
            v(i,j,k) = 0._rp
            w(i,j,k) = 0._rp
            p(i,j,k) = 0._rp
          enddo
        enddo
      enddo
    endif
    if(is_noise) then
      call add_noise(lo,hi,ng,123,.5_rp,u)
      call add_noise(lo,hi,ng,456,.5_rp,v)
      call add_noise(lo,hi,ng,789,.5_rp,w)
    endif
    if(is_mean) then
      call set_mean(lo,hi,l,dxc,dyf,dzf,uref,u)
    endif
    if(is_wallturb) is_pair = .true.
    if(is_pair) then
      !
      ! initialize a streamwise vortex pair for a fast transition
      ! to turbulence in a pressure-driven channel:
      !        psi(x,y,z)  = f(z)*g(x,y), with
      !        f(z)        = (1-z**2)**2, and
      !        g(x,y)      = y*exp[-(16x**2-4y**2)]
      ! (x,y,z) --> (streamwise, spanwise, wall-normal) directions
      !
      ! see Henningson and Kim, JFM 1991
      !
      do k=lo(3),hi(3)
        zcl = 2._rp*zc(k)/l(3) - 1._rp ! z rescaled to be between -1 and +1
        zfl = 2._rp*zf(k)/l(3) - 1._rp
        do j=lo(2),hi(2)
          ycl = 2._rp*yc(j)/l(2) - 1._rp ! y rescaled to be between -1 and +1
          yfl = 2._rp*yf(j)/l(2) - 1._rp
          do i=lo(1),hi(1)
            xcl = 2._rp*xc(i)/l(1) - 1._rp ! x rescaled to be between -1 and +1
            xfl = 2._rp*xf(i)/l(1) - 1._rp
            v(i,j,k) = -1._rp*gxy(yfl,xcl)*dfz(zcl)*uref
            w(i,j,k) =  1._rp*fz(zfl)*dgxy(ycl,xcl)*uref
            p(i,j,k) =  0._rp
          enddo
        enddo
      enddo
      !
      ! alternatively, using a Taylor-Green vortex 
      ! for the cross-stream velocity components
      ! (commented below)
      !
      !do k=lo(3),hi(3)
      !  zcl = zc(k)/l(3)*2._rp*pi
      !  zfl = zf(k)/l(3)*2._rp*pi
      !  do j=lo(2),hi(2)
      !    ycl = yc(j)/l(2)*2._rp*pi
      !    yfl = yf(j)/l(2)*2._rp*pi
      !    do i=lo(1),hi(1)
      !      xcl = xc(i)/l(1)*2._rp*pi
      !      xfl = xf(i)/l(1)*2._rp*pi
      !      v(i,j,k) =  sin(xcl)*cos(yfl)*cos(zcl)
      !      w(i,j,k) = -cos(xcl)*sin(ycl)*cos(zfl)
      !      p(i,j,k) = 0._rp!(cos(2._rp*xcl)+cos(2._rp*ycl))*(cos(2._rp*zcl)+2._rp)/16._rp
      !    enddo
      !  enddo
      !enddo
    endif
    deallocate(u1d)
    return
  end subroutine initflow
  !
  subroutine add_noise(lo,hi,ng,iseed,norm,p)
    implicit none
    integer , intent(in), dimension(3) :: lo,hi,ng
    integer , intent(in) :: iseed
    real(rp), intent(in) :: norm
    real(rp), intent(inout), dimension(lo(1)-1:,lo(2)-1:,lo(3)-1:) :: p
    integer(4), allocatable, dimension(:) :: seed
    real(rp) :: rn
    integer :: i,j,k
    allocate(seed(64))
    seed(:) = iseed
    call random_seed( put = seed )
    do k=1,ng(3)
      do j=1,ng(2)
        do i=1,ng(1)
          call random_number(rn)
          if(i.ge.lo(1).and.i.le.hi(1) .and. &
             j.ge.lo(2).and.j.le.hi(2) .and. &
             k.ge.lo(3).and.k.le.hi(3) ) then
             p(i,j,k) = p(i,j,k) + 2._rp*(rn-.5_rp)*norm
          endif
        enddo
      enddo
    enddo
    return
  end subroutine add_noise
  !
  subroutine set_mean(lo,hi,l,dx,dy,dz,mean,p)
    implicit none
    integer , intent(in), dimension(3) :: lo,hi
    real(rp), intent(in), dimension(3) :: l
    real(rp), intent(in), dimension(lo(1)-1:) :: dx
    real(rp), intent(in), dimension(lo(2)-1:) :: dy
    real(rp), intent(in), dimension(lo(3)-1:) :: dz
    real(rp), intent(in) :: mean
    real(rp), intent(inout), dimension(lo(1)-1:,lo(2)-1:,lo(3)-1:) :: p
    real(rp) :: meanold
    integer :: i,j,k
    meanold = 0._rp
    !
    !$OMP PARALLEL DO DEFAULT(none) &
    !$OMP SHARED(lo,hi,l,dx,dy,dz,p) &
    !$OMP PRIVATE(i,j,k) &
    !$OMP REDUCTION(+:meanold)
    do k=lo(3),hi(3)
      do j=lo(2),hi(2)
        do i=lo(1),hi(1)
          meanold = meanold + p(i,j,k)*dx(i)*dy(j)*dz(k)/(l(1)*l(2)*l(3))
        enddo
      enddo
    enddo
    !$OMP END PARALLEL DO
    call mpi_allreduce(MPI_IN_PLACE,meanold,1,MPI_REAL_RP,MPI_SUM,MPI_COMM_WORLD,ierr)
    if(meanold.ne.0._rp) then
      !$OMP WORKSHARE
      p(:,:,:) = p(:,:,:)/meanold*mean
      !$OMP END WORKSHARE
    endif
    return
  end subroutine set_mean
  !
  subroutine couette(lo,hi,zc,l,norm,p)
    !
    ! plane couette profile normalized by the wall velocity difference
    !
    implicit none
    integer , intent(in)   :: lo,hi
    real(rp), intent(in), dimension(lo-1:) :: zc
    real(rp), intent(in)   :: l,norm
    real(rp), intent(out), dimension(lo:) :: p
    integer :: k
    real(rp) :: z
    do k=lo,hi
      z    = zc(k)/l
      p(k) = .5_rp*(1._rp-2._rp*z)*norm
    enddo
    return
  end subroutine couette
  !
  subroutine poiseuille(lo,hi,zc,l,norm,p)
    implicit none
    integer , intent(in)   :: lo,hi
    real(rp), intent(in), dimension(lo-1:) :: zc
    real(rp), intent(in)   :: l,norm
    real(rp), intent(out), dimension(lo:) :: p
    integer :: k
    real(rp) :: z
    !
    ! plane poiseuille profile normalized by the bulk velocity
    !
    do k=lo,hi
      z    = zc(k)/l
      p(k) = 6._rp*z*(1._rp-z)*norm
    enddo
    return
  end subroutine poiseuille
  !
  subroutine log_profile(lo,hi,zc,l,uref,lref,visc,p)
    implicit none
    integer , intent(in)   :: lo,hi
    real(rp), intent(in), dimension(lo-1:) :: zc
    real(rp), intent(in)   :: l,uref,lref,visc
    real(rp), intent(out), dimension(lo:) :: p
    integer :: k
    real(rp) :: z,reb,retau ! z/lz and bulk Reynolds number
    reb = lref*uref/visc
    retau = 0.09_rp*reb**(0.88_rp) ! from Pope's book
    do k=lo,hi
      z    = zc(k)/l
      if(z.gt.0.5_rp) z = 1._rp-z
      z    = zc(k)*2._rp*retau
      p(k) = 2.5_rp*log(z) + 5.5_rp
      if (z.le.11.6_rp) p(k)=z
    enddo
    return
  end subroutine log_profile
  !
  ! functions to initialize the streamwise vortex pair
  ! (explained above)
  !
  function fz(zc)
  real(rp), intent(in) :: zc
  real(rp) :: fz
    fz = ((1._rp-zc**2)**2)
  end function
  !
  function dfz(zc)
  real(rp), intent(in) :: zc
  real(rp) :: dfz
    dfz = -4._rp*zc*(1._rp-zc**2)
  end function
  !
  function gxy(xc,yc)
  real(rp), intent(in) :: xc,yc
  real(rp) :: gxy
    gxy = yc*exp(-4._rp*(4._rp*xc**2+yc**2))
  end function
  !
  function dgxy(xc,yc)
  real(rp), intent(in) :: xc,yc
  real(rp) :: dgxy
    dgxy = exp(-4._rp*(4._rp*xc**2+yc**2))*(1._rp-8._rp*yc**2)
  end function
end module mod_initflow
