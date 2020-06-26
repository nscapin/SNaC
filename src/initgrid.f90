module mod_initgrid
  use mod_common_mpi, only:ierr
  use mod_param     , only:pi
  use mod_types
  implicit none
  private
  public initgrid,distribute_grid,bound_grid,save_grid
  contains
  subroutine initgrid(lo,hi,gt,gr,lmin,lmax,drc_g,drf_g,rc_g,rf_g)
    !
    ! initializes a non-uniform grid
    !
    ! NEEDS TO BE PROBABLY SLIGHTLY ADAPTED IN CASE IT IS IN THE MIDDLE OF A BLOCK
    !
    implicit none
    integer, parameter :: CLUSTER_TWO_END = 0, &
                          CLUSTER_ONE_END = 1, &
                          CLUSTER_MIDDLE  = 2
    integer         , intent(in )                  :: lo,hi,gt
    real(rp)        , intent(in )                  :: gr,lmin,lmax
    real(rp)        , intent(out), dimension(lo-1:) :: drc_g,drf_g,rc_g,rf_g
    real(rp) :: r0
    integer :: q,n
    procedure (), pointer :: gridpoint => null()
    select case(gt)
    case(CLUSTER_TWO_END)
      gridpoint => gridpoint_cluster_two_end
    case(CLUSTER_ONE_END)
      gridpoint => gridpoint_cluster_middle
    case(CLUSTER_MIDDLE)
      gridpoint => gridpoint_cluster_one_end
    case default
      gridpoint => gridpoint_cluster_two_end
    end select
    !
    ! step 1) determine coordinates of cell faces rf
    !
    do q=lo,hi
      n  = hi-lo+1
      r0 = (q-lo+1-0._rp)/(1._rp*n)
      call gridpoint(gr,r0,rf_g(q))
      rf_g(q) = lmin + rf_g(q)*(lmax-lmin)
    enddo
    rf_g(lo-1) = lmin
    !
    ! step 2) determine grid spacing between faces drf
    !
    do q=lo,hi
      drf_g(q) = rf_g(q)-rf_g(q-1)
    enddo
    drf_g(lo-1) = drf_g(lo)
    drf_g(hi+1) = drf_g(hi)
    !
    ! step 3) determine grid spacing between centers drc
    !
    do q=lo-1,hi
      drc_g(q) = .5_rp*(drf_g(q)+drf_g(q+1))
    enddo
    drc_g(hi+1) = drc_g(hi)
    !
    ! step 4) compute coordinates of cell centers rc and faces rf
    !
    rc_g(lo-1)    = -drc_g(lo-1)/2._rp
    rf_g(lo-1)    = 0._rp
    do q=lo,hi+1
      rc_g(q) = rc_g(q-1) + drc_g(q-1)
      rf_g(q) = rf_g(q-1) + drf_g(q  )
    enddo
    !
    return
  end subroutine initgrid
  subroutine distribute_grid(lo_g,lo,hi,grid_g,grid)
    implicit none
    integer , intent(in )                     :: lo_g,lo,hi
    real(rp), intent(in ), dimension(lo_g-1:) :: grid_g
    real(rp), intent(out), dimension(lo  -1:) :: grid
    grid(lo-1:hi+1) = grid_g(lo-1:hi+1)
    return
  end subroutine distribute_grid
  subroutine bound_grid(lo_g,hi_g,lo,hi,nb,grid)
    implicit none
    integer , intent(in   )                     :: lo_g,hi_g,lo,hi
    integer , intent(in   ), dimension(0:1)     :: nb
    real(rp), intent(inout), dimension(lo  -1:) :: grid
    if(lo == lo_g .or. hi == hi_g) then
      call MPI_SENDRECV(grid(lo  ),1,MPI_REAL_RP,nb(0),0, &
                        grid(hi+1),1,MPI_REAL_RP,nb(1),0, &
                        MPI_COMM_WORLD,MPI_STATUS_IGNORE,ierr)
      call MPI_SENDRECV(grid(hi  ),1,MPI_REAL_RP,nb(1),0, &
                        grid(lo-1),1,MPI_REAL_RP,nb(0),0, &
                        MPI_COMM_WORLD,MPI_STATUS_IGNORE,ierr)
    endif
    return
  end subroutine bound_grid
  subroutine save_grid(fname,lo_g,hi_g,rf_g,rc_g,drf_g,drc_g)
    implicit none
    character(len=*), intent(in) :: fname
    integer         , intent(in) :: lo_g,hi_g
    real(rp)        , intent(in), dimension(lo_g-1:) :: rf_g,rc_g,drf_g,drc_g
    integer :: iunit,q,reclen
    !
    inquire(iolength=reclen) rf_g(lo_g:hi_g),rc_g(lo_g:hi_g),drf_g(lo_g:hi_g),drc_g(lo_g:hi_g)
    open(newunit=iunit,file=trim(fname)//'.bin',status='replace',access='direct',recl=reclen)
    write(iunit,rec=1) rf_g(lo_g:hi_g),rc_g(lo_g:hi_g),drf_g(lo_g:hi_g),drc_g(lo_g:hi_g)
    close(iunit)
    open(newunit=iunit,status='replace',file=trim(fname)//'.out')
    do q=lo_g-1,hi_g+1
      write(iunit,'(5E15.7)') 0._rp,rf_g(q),rc_g(q),drf_g(q),drc_g(q)
    enddo
    close(iunit)
    return
  end subroutine save_grid
  !
  ! grid stretching functions 
  ! see e.g., Fluid Flow Phenomena -- A Numerical Toolkit, by P. Orlandi
  !           Pirozzoli et al. JFM 788, 614–639 (commented)
  !
  subroutine gridpoint_cluster_two_end(alpha,r0,r)
    !
    ! clustered at the two sides
    !
    implicit none
    real(rp), intent(in ) :: alpha,r0
    real(rp), intent(out) :: r
    if(alpha /= 0._rp) then
      r = 0.5_rp*(1._rp+tanh((r0-0.5_rp)*alpha)/tanh(alpha/2._rp))
      !r = 0.5_rp*(1._rp+erf( (r0-0.5_rp)*alpha)/erf( alpha/2._rp))
    else
      r = r0
    endif
    return
  end subroutine gridpoint_cluster_two_end
  subroutine gridpoint_cluster_one_end(alpha,r0,r)
    !
    ! clustered at the lower side
    !
    implicit none
    real(rp), intent(in ) :: alpha,r0
    real(rp), intent(out) :: r
    if(alpha /= 0._rp) then
      r = 1.0_rp*(1._rp+tanh((r0-1.0_rp)*alpha)/tanh(alpha/1._rp))
      !r = 1.0_rp*(1._rp+erf( (r0-1.0_rp)*alpha)/erf( alpha/1._rp))
    else
      r = r0
    endif
    return
  end subroutine gridpoint_cluster_one_end
  subroutine gridpoint_cluster_middle(alpha,r0,r)
    !
    ! clustered in the middle
    !
    implicit none
    real(rp), intent(in ) :: alpha,r0
    real(rp), intent(out) :: r
    if(alpha /= 0._rp) then
      if(    r0 <= 0.5_rp) then 
        r = 0.5_rp*(1._rp-1._rp+tanh(2._rp*alpha*(r0-0._rp))/tanh(alpha))
        !r = 0.5_rp*(1._rp-1._rp+erf( 2._rp*alpha*(r0-0._rp))/erf( alpha))
      elseif(r0 >  0.5_rp) then
        r = 0.5_rp*(1._rp+1._rp+tanh(2._rp*alpha*(r0-1._rp))/tanh(alpha))
        !r = 0.5_rp*(1._rp+1._rp+erf( 2._rp*alpha*(r0-1._rp))/erf( alpha))
      endif
    else
      r = r0
    endif
    return
  end subroutine gridpoint_cluster_middle
end module mod_initgrid
