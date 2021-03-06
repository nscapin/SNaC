module mod_output
  use mpi
  use mod_common_mpi, only: ierr,myid
  use mod_load      , only: io_field 
  use mod_types
  implicit none
  private
  public out0d,out1d,out3d,write_log_output,write_visu_3d
  contains
  subroutine out0d(fname,n,var)
    !
    ! appends the first n entries of an array
    ! var to a file
    ! fname -> name of the file
    ! n     -> number of entries
    ! var   -> input array of real values
    !
    implicit none
    character(len=*), intent(in) :: fname
    integer , intent(in) :: n
    real(rp), intent(in), dimension(:) :: var
    integer :: iunit
    character(len=30) :: cfmt
    integer :: i
    !
    write(cfmt,'(A,I3,A)') '(',n,'E15.7)'
    if (myid == 0) then
      open(newunit=iunit,file=fname,position='append')
      write(iunit,trim(cfmt)) (var(i),i=1,n) 
      close(iunit)
    endif
  end subroutine out0d
  !
  subroutine out1d(fname,lo,hi,ng,idir,l,dx,dy,dz,x,y,z,x_g,y_g,z_g,p)
    !
    ! writes the profile of a variable averaged
    ! over two domain directions
    !
    ! fname    -> name of the file
    ! lo,hi    -> local lower and upper bounds of input array 
    !             in global coordinates
    ! ng       -> global sizes of the input array
    ! idir     -> direction of the profile
    ! l        -> domain dimensions
    ! dx,dy,dz -> grid spacings
    !  x, y, z -> coodinates of grid points
    ! p        -> 3D input scalar field
    !
    implicit none
    character(len=*), intent(in) :: fname
    integer , intent(in), dimension(3) :: lo,hi,ng
    integer , intent(in) :: idir
    real(rp), intent(in), dimension(3) :: l
    real(rp), intent(in), dimension(lo(1)-1:) :: x,dx
    real(rp), intent(in), dimension(lo(2)-1:) :: y,dy
    real(rp), intent(in), dimension(lo(3)-1:) :: z,dz
    real(rp), intent(in), dimension(1-1    :) :: x_g
    real(rp), intent(in), dimension(1-1    :) :: y_g
    real(rp), intent(in), dimension(1-1    :) :: z_g
    real(rp), intent(in), dimension(lo(1)-1:,lo(2)-1:,lo(3)-1:) :: p
    real(rp), allocatable, dimension(:) :: p1d
    integer :: i,j,k
    integer :: iunit
    !
    select case(idir)
    case(3)
      allocate(p1d(ng(3)))
      p1d(:) = 0._rp
      do k=lo(3),hi(3)
        do j=lo(2),hi(2)
          do i=lo(1),hi(1)
            p1d(k) = p1d(k) + p(i,j,k)*dx(i)*dy(j)/(l(1)*l(2))
          enddo
        enddo
      enddo
      call mpi_allreduce(MPI_IN_PLACE,p1d(1),ng(3),MPI_REAL_RP,MPI_SUM,MPI_COMM_WORLD,ierr)
      if(myid == 0) then
        open(newunit=iunit,file=fname)
        do k=1,ng(3)
          write(iunit,'(2E15.7)') z_g(k),p1d(k)
        enddo
        close(iunit)
      endif
    case(2)
      allocate(p1d(ng(2)))
      p1d(:) = 0._rp
      do j=lo(2),hi(2)
        do k=lo(3),hi(3)
          do i=lo(1),hi(1)
            p1d(j) = p1d(j) + p(i,j,k)*dx(i)*dz(k)/(l(1)*l(3))
          enddo
        enddo
      enddo
      call mpi_allreduce(MPI_IN_PLACE,p1d(1),ng(2),MPI_REAL_RP,MPI_SUM,MPI_COMM_WORLD,ierr)
      if(myid == 0) then
        open(newunit=iunit,file=fname)
        do j=1,ng(2)
          write(iunit,'(2E15.7)') y_g(j),p1d(j)
        enddo
        close(iunit)
      endif
    case(1)
      allocate(p1d(ng(1)))
      p1d(:) = 0._rp
      do i=lo(1),hi(1)
        do k=lo(3),hi(3)
          do j=lo(2),hi(2)
            p1d(i) = p1d(i) + p(i,j,k)*dy(j)*dz(k)/(l(2)*l(3))
          enddo
        enddo
      enddo
      call mpi_allreduce(MPI_IN_PLACE,p1d(1),ng(1),MPI_REAL_RP,MPI_SUM,MPI_COMM_WORLD,ierr)
      if(myid == 0) then
        open(newunit=iunit,file=fname)
        do i=1,ng(1)
          write(iunit,'(2E15.7)') x_g(i),p1d(i)
        enddo
        close(iunit)
      endif
    end select
    deallocate(p1d)
  end subroutine out1d
  !
  subroutine out3d(fname,lo,hi,ng,nskip,p)
    !
    ! saves a 3D scalar field into a binary file
    !
    ! fname  -> name of the output file
    ! lo,hi  -> local lower and upper bounds of input array 
    !           in global coordinates
    ! ng     -> global sizes of the input array
    ! nskip  -> array with the step size for which the
    !           field is written; i.e.: (/1,1,1/)
    !           writes the full field
    !           n.b.: not implemented for now; it will 
    !                 always write the full array
    ! p      -> 3D input scalar field
    !
    implicit none
    character(len=*), intent(in) :: fname
    integer , intent(in   ), dimension(3) :: lo,hi,ng,nskip
    real(rp), intent(inout), dimension(lo(1)-1,lo(2)-1,lo(3)-1) :: p
    integer :: fh
    integer(kind=MPI_OFFSET_KIND) :: filesize,disp
    !
    call MPI_FILE_OPEN(MPI_COMM_WORLD, fname, &
         MPI_MODE_CREATE+MPI_MODE_WRONLY, MPI_INFO_NULL,fh, ierr)
    filesize = 0_MPI_OFFSET_KIND
    call MPI_FILE_SET_SIZE(fh,filesize,ierr)
    disp = 0_MPI_OFFSET_KIND
    call io_field('w',fh,ng,[1,1,1],lo,hi,disp,p)
    call MPI_FILE_CLOSE(fh,ierr)
  end subroutine out3d
  !
  subroutine write_log_output(fname,fname_fld,varname,nmin,nmax,nskip,time,istep)
    !
    ! appends information about a saved binary file to a log file
    ! this file is used to generate a xdmf file for visualization of field data
    !
    ! fname     -> name of the output log file
    ! fname_fld -> name of the saved binary file (excluding the directory)
    ! varname   -> name of the variable that is saved
    ! nmin      -> first element of the field that is saved in each direction, e.g. (/1,1,1/)
    ! nmax      -> last  element of the field that is saved in each direction, e.g. (/ng(1),ng(2),ng(3)/)
    ! nskip     -> step size between nmin and nmax, e.g. (/1,1,1/) if the whole array is saved
    ! time      -> physical time
    ! istep     -> time step number
    !
    implicit none
    character(len=*), intent(in) :: fname,fname_fld,varname
    integer , intent(in), dimension(3) :: nmin,nmax,nskip
    real(rp), intent(in)               :: time
    integer , intent(in)               :: istep
    character(len=100) :: cfmt
    integer :: iunit
    !
    iunit = 10
    write(cfmt, '(A)') '(A,A,A,9i5,E15.7,i7)'
    if (myid == 0) then
      open(iunit,file=fname,position='append')
      write(iunit,trim(cfmt)) trim(fname_fld),' ',trim(varname),nmin,nmax,nskip,time,istep
      close(iunit)
    endif
  end subroutine write_log_output
  !
  subroutine write_visu_3d(datadir,fname_bin,fname_log,varname,lo,hi,ng,nmin,nmax,nskip,time,istep,p)
    !
    ! wraps the calls of out3d and write_log_output into the same subroutine
    !
    implicit none
    character(len=*), intent(in)          :: datadir,fname_bin,fname_log,varname
    integer , intent(in   ), dimension(3)    :: lo,hi,ng,nmin,nmax,nskip
    real(rp), intent(in   )                  :: time
    integer , intent(in   )                  :: istep
    real(rp), intent(inout), dimension(lo(1)-1:,lo(2)-1:,lo(3)-1:) :: p
    !
    call out3d(trim(datadir)//trim(fname_bin),lo,hi,ng,nskip,p)
    call write_log_output(trim(datadir)//trim(fname_log),trim(fname_bin),trim(varname),nmin,nmax,nskip,time,istep)
  end subroutine write_visu_3d
end module mod_output
