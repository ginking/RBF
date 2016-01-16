# distutils: extra_compile_args = -fopenmp 
# distutils: extra_link_args = -fopenmp
'''
Description 
----------- 
  Defines functions for basic computational geometry in 1, 2, and 3
  dimensions. This modules requires all volumes, surfaces and segments
  to be described as simplicial complexes, that is, as a collection of
  simplexes defined by their vertices.  Most end user functions in
  this module have a vertices and simplices argument, the former is a
  (N,D) collection of all D dimensional vertices in the simplicial
  complex and the latter is an (M,D) array of vertex indices making up
  each simplex. For example the unit square in two dimensions can be
  described as collection of line segments:

  >>> vertices = [[0.0,0.0],
                  [1.0,0.0],
                  [1.0,1.0],
                  [0.0,1.0]]
  >>> simplices = [[0,1],
                   [1,2],
                   [2,3],
                   [3,0]]

  A three dimensional cube can similarly be described as a collection
  of triangles:

  >>> vertices = [[0.0,0.0,0.0],
                  [0.0,0.0,1.0],
                  [0.0,1.0,0.0],
                  [0.0,1.0,1.0],
                  [1.0,0.0,0.0],
                  [1.0,0.0,1.0],
                  [1.0,1.0,0.0],
                  [1.0,1.0,1.0]]
  >>> simplices = [[0,1,4],
                   [1,5,4],
                   [1,7,5],
                   [1,3,7],
                   [0,1,3],
                   [0,2,3],
                   [0,2,6],
                   [0,4,6],
                   [4,5,7],
                   [4,6,7],
                   [2,3,7],
                   [2,6,7]]

  Although the notation is clumsy, a 1D domains can be described as a
  collection of vertices in a manner that is consistent with the above
  two examples:
   
  >>> vertices = [[0.0],[1.0]]
  >>> simplices = [[0],[1]]

  This module is primarily use to find whether and where line segments
  intersect a simplicial complex and whether points are contained
  within a closed simplicial complex.  For example, one can determine
  whether a collection of points, saved as 'points', are contained
  within a simplicial complex, defined by 'vertices' and 'simplices'
  with the command

  >>> complex_contains(points,vertices,simplices)

  which returns a boolean array.

  One can find the number of times a collection of line segments,
  defined by 'start_points' and 'end_points', intersect a simplicial
  complex with the command

  >> complex_cross_count(start_points,end_points,vertices,simplices)

  which returns an array of the number of simplexes intersections for
  each segment. If it is known that a collection of line segments
  intersect a simplicial complex then the intersection point can be
  found with the command

  >> complex_intersection(start_points,end_points,vertices,simplices)
 
  This returns an (N,D) array of intersection points where N is the
  number of line segments.  If a line segment does not intersect the 
  simplicial complex then the above command returns a ValueError. If
  there are multiple intersections for a single segment then only the 
  first detected intersection will be returned.

'''
import numpy as np
cimport numpy as np
from cython.parallel cimport prange
from cython cimport boundscheck,wraparound,cdivision
from libc.stdlib cimport rand
from libc.stdlib cimport malloc,free
from itertools import combinations

# NOTE: fabs is not the same as abs in C!!! 
cdef extern from "math.h":
  cdef float fabs(float x) nogil

cdef extern from "math.h":
  cdef float sqrt(float x) nogil

cdef extern from "limits.h":
    int RAND_MAX

cdef struct vector2d:
  double x
  double y

cdef struct segment2d:
  vector2d a
  vector2d b

cdef struct vector3d:
  double x
  double y
  double z

cdef struct segment3d:
  vector3d a
  vector3d b

cdef struct triangle3d:
  vector3d a
  vector3d b
  vector3d c


cdef double min2(double a, double b) nogil:
  if a <= b:
    return a
  else:
    return b

cdef double max2(double a, double b) nogil:
  if a >= b:
    return a
  else:
    return b

cdef double min3(double a, double b, double c) nogil:
  if (a <= b) & (a <= c):
    return a

  if (b <= a) & (b <= c):
    return b

  if (c <= a) & (c <= b):
    return c


@boundscheck(False)
@wraparound(False)
@cdivision(True)
cdef vector2d find_outside_2d(double[:,:] v) nogil:
  cdef:
    unsigned int i
    vector2d out
    
  out.x = v[0,0]
  out.y = v[0,1]
  for i in range(1,v.shape[0]):
    if v[i,0] < out.x:
      out.x = v[i,0] 

    if v[i,1] < out.y:
      out.y = v[i,1] 

  out.x -= 1.23456789# + rand()*1.0/RAND_MAX
  out.y -= 2.34567891# + rand()*1.0/RAND_MAX

  return out

@boundscheck(False)
@wraparound(False)
@cdivision(True)
cdef vector3d find_outside_3d(double[:,:] v) nogil:
  cdef:
    unsigned int i
    vector3d out
    
  out.x = v[0,0]
  out.y = v[0,1]
  out.z = v[0,2]
  for i in range(1,v.shape[0]):
    if v[i,0] < out.x:
      out.x = v[i,0] 

    if v[i,1] < out.y:
      out.y = v[i,1] 

    if v[i,2] < out.z:
      out.z = v[i,2] 

  out.x -= 1.23456789# + rand()*1.0/RAND_MAX
  out.y -= 2.34567891# + rand()*1.0/RAND_MAX
  out.z -= 3.45678912# + rand()*1.0/RAND_MAX
  return out


@boundscheck(False)
@wraparound(False)
@cdivision(True)
cdef bint is_intersecting_2d(segment2d seg1,
                             segment2d seg2) nogil:
  '''
  Description
  -----------
    Identifies whether two 2D segments intersect. An intersection is
    detected if both segments are not colinear and if any part of the
    two segments touch
  '''
  cdef:
    double proj1,proj2,n1,n2
    vector2d pnt

  # find the normal vector components for segment 2
  n1 =  (seg2.b.y-seg2.a.y)
  n2 = -(seg2.b.x-seg2.a.x)

  # project both points in segment 1 onto the normal vector
  proj1 = ((seg1.a.x-seg2.a.x)*n1 +
           (seg1.a.y-seg2.a.y)*n2)
  proj2 = ((seg1.b.x-seg2.a.x)*n1 +
           (seg1.b.y-seg2.a.y)*n2)

  if proj1*proj2 > 0:
    return False

  # return false if the segments are collinear
  if (proj1 == 0) & (proj2 == 0):
    return False

  # find the point where segment 1 intersects the line overlapping 
  # segment 2 
  pnt.x = seg1.a.x + (proj1/(proj1-proj2))*(
          (seg1.b.x-seg1.a.x))
  pnt.y = seg1.a.y + (proj1/(proj1-proj2))*(
          (seg1.b.y-seg1.a.y))

  # if the normal x component is larger then compare y values
  if fabs(n1) >= fabs(n2):
    if ((pnt.y >= min2(seg2.a.y,seg2.b.y)) & 
        (pnt.y <= max2(seg2.a.y,seg2.b.y))):
      return True
    else:
      return False

  else:
    if ((pnt.x >= min2(seg2.a.x,seg2.b.x)) & 
        (pnt.x <= max2(seg2.a.x,seg2.b.x))):
      return True
    else:
      return False


@boundscheck(False)
@wraparound(False)
cdef np.ndarray cross_count_2d(double[:,:] start_pnts,
                                double[:,:] end_pnts,
                                double[:,:] vertices,
                                long[:,:] simplices):
  '''
  Description
  -----------
    returns an array containing the number of simplexes intersected
    between start_pnts and end_pnts.

  '''
  cdef:
    int i
    int N = start_pnts.shape[0]
    long[:] out = np.empty((N,),dtype=int,order='c')
    segment2d *seg_array = <segment2d *>malloc(N*sizeof(segment2d))
    
  if not seg_array:
    raise MemoryError()

  try:
    with nogil:
      for i in prange(N):
        seg_array[i].a.x = start_pnts[i,0]
        seg_array[i].a.y = start_pnts[i,1]
        seg_array[i].b.x = end_pnts[i,0]
        seg_array[i].b.y = end_pnts[i,1]
        out[i] = _cross_count_2d(seg_array[i],vertices,simplices)

  finally:
    free(seg_array)

  return np.asarray(out,dtype=int)


@boundscheck(False)
@wraparound(False)
cdef int _cross_count_2d(segment2d seg,
                         double[:,:] vertices,
                         long[:,:] simplices) nogil:
  cdef:
    unsigned int i
    unsigned int count = 0
    segment2d dummy_seg

  for i in range(simplices.shape[0]):
    dummy_seg.a.x = vertices[simplices[i,0],0]
    dummy_seg.a.y = vertices[simplices[i,0],1]
    dummy_seg.b.x = vertices[simplices[i,1],0]
    dummy_seg.b.y = vertices[simplices[i,1],1]
    if is_intersecting_2d(seg,dummy_seg):
      count += 1

  return count


@boundscheck(False)
@wraparound(False)
cdef np.ndarray cross_which_2d(double[:,:] start_pnts,
                               double[:,:] end_pnts,
                               double[:,:] vertices,
                               long[:,:] simplices):
  '''
  Description
  -----------
    returns an array identifying which simplex is intersected by
    start_pnts and end_pnts. 

  Note
  ----
    if there is no intersection then a ValueError is returned.

  '''
  cdef:
    int i
    int N = start_pnts.shape[0]
    long[:] out = np.empty((N,),dtype=int,order='c')
    segment2d *seg_array = <segment2d *>malloc(N*sizeof(segment2d))
    
  if not seg_array:
    raise MemoryError()
  
  try:
    for i in range(N):
      seg_array[i].a.x = start_pnts[i,0]
      seg_array[i].a.y = start_pnts[i,1]
      seg_array[i].b.x = end_pnts[i,0]
      seg_array[i].b.y = end_pnts[i,1]
      out[i] = _cross_which_2d(seg_array[i],vertices,simplices)

  finally:
    free(seg_array)

  return np.asarray(out)


@boundscheck(False)
@wraparound(False)
cdef int _cross_which_2d(segment2d seg,
                         double[:,:] vertices,
                         long[:,:] simplices) except *:
  cdef:
    int i
    segment2d dummy_seg
  
  for i in range(simplices.shape[0]):
    dummy_seg.a.x = vertices[simplices[i,0],0]
    dummy_seg.a.y = vertices[simplices[i,0],1]
    dummy_seg.b.x = vertices[simplices[i,1],0]
    dummy_seg.b.y = vertices[simplices[i,1],1]
    if is_intersecting_2d(seg,dummy_seg):
      return i

  raise ValueError('No intersection found for segment [[%s,%s],[%s,%s]]' % 
                   (seg.a.x,seg.a.y,seg.b.x,seg.b.y))

@boundscheck(False)
@wraparound(False)
cdef np.ndarray cross_where_2d(double[:,:] start_pnts,
                               double[:,:] end_pnts,
                               double[:,:] vertices,
                               long[:,:] simplices):         
  '''
  Description
  -----------
    returns an array of intersection points between line segments,
    defined in terms of start_pnts and end_pnts, and simplices. 

  Note
  ----
    if there is no intersection then a ValueError is returned.

  '''
  cdef:
    int i
    int N = start_pnts.shape[0]
    double[:,:] out = np.empty((N,2),dtype=float,order='c')
    vector2d vec
    segment2d *seg_array = <segment2d *>malloc(N*sizeof(segment2d))

  if not seg_array:
    raise MemoryError()

  try:
    for i in range(N):
      seg_array[i].a.x = start_pnts[i,0]
      seg_array[i].a.y = start_pnts[i,1]
      seg_array[i].b.x = end_pnts[i,0]
      seg_array[i].b.y = end_pnts[i,1]
      vec = _cross_where_2d(seg_array[i],vertices,simplices)
      out[i,0] = vec.x
      out[i,1] = vec.y

  finally:
    free(seg_array)

  return np.asarray(out)


@boundscheck(False)
@wraparound(False)
@cdivision(True)
cdef vector2d _cross_where_2d(segment2d seg,
                              double[:,:] vertices,
                              long[:,:] simplices) except *:
  cdef:
    int idx
    double proj1,proj2,n1,n2
    segment2d dummy_seg
    vector2d out

  idx = _cross_which_2d(seg,vertices,simplices)
  dummy_seg.a.x = vertices[simplices[idx,0],0]
  dummy_seg.a.y = vertices[simplices[idx,0],1]
  dummy_seg.b.x = vertices[simplices[idx,1],0]
  dummy_seg.b.y = vertices[simplices[idx,1],1]

  n1 =  (dummy_seg.b.y-dummy_seg.a.y)
  n2 = -(dummy_seg.b.x-dummy_seg.a.x)

  proj1 = ((seg.a.x-dummy_seg.a.x)*n1 +
           (seg.a.y-dummy_seg.a.y)*n2)
  proj2 = ((seg.b.x-dummy_seg.a.x)*n1 +
           (seg.b.y-dummy_seg.a.y)*n2)

  out.x = seg.a.x + (proj1/(proj1-proj2))*(
           (seg.b.x-seg.a.x))
  out.y = seg.a.y + (proj1/(proj1-proj2))*(
           (seg.b.y-seg.a.y))

  return out


@boundscheck(False)
@wraparound(False)
cdef np.ndarray cross_normals_2d(double[:,:] start_pnts,
                                 double[:,:] end_pnts,
                                 double[:,:] vertices,
                                 long[:,:] simplices):         
  '''
  Description
  -----------
    returns an array of normal vectors to the simplices intersected by
    the line segments described in terms of start_pnts and end_pnts

  Note
  ----
    if there is not intersection then a ValueError is returned

  '''
  cdef:
    int i
    int N = start_pnts.shape[0]
    double[:,:] out = np.empty((N,2),dtype=float,order='c')
    segment2d *seg_array = <segment2d *>malloc(N*sizeof(segment2d))
    vector2d vec

  if not seg_array:
    raise MemoryError()

  try:
    for i in range(N):
      seg_array[i].a.x = start_pnts[i,0]
      seg_array[i].a.y = start_pnts[i,1]
      seg_array[i].b.x = end_pnts[i,0]
      seg_array[i].b.y = end_pnts[i,1]
      vec = _cross_normals_2d(seg_array[i],vertices,simplices)
      out[i,0] = vec.x
      out[i,1] = vec.y
    
  finally:
    free(seg_array)

  return np.asarray(out)  


@boundscheck(False)
@wraparound(False)
@cdivision(True)
cdef vector2d _cross_normals_2d(segment2d seg,
                                double[:,:] vertices,
                                long[:,:] simplices) except *:      
  cdef:
    double proj,n
    int idx
    segment2d dummy_seg
    vector2d vec

  idx = _cross_which_2d(seg,vertices,simplices)
  dummy_seg.a.x = vertices[simplices[idx,0],0]
  dummy_seg.a.y = vertices[simplices[idx,0],1]
  dummy_seg.b.x = vertices[simplices[idx,1],0]
  dummy_seg.b.y = vertices[simplices[idx,1],1]

  vec.x =  (dummy_seg.b.y-dummy_seg.a.y)
  vec.y = -(dummy_seg.b.x-dummy_seg.a.x)
  proj = ((seg.b.x-dummy_seg.a.x)*vec.x +
          (seg.b.y-dummy_seg.a.y)*vec.y)
  if proj <= 0:
    vec.x *= -1
    vec.y *= -1

  n = sqrt(vec.x**2 + vec.y**2)
  vec.x /= n
  vec.y /= n

  return vec


@boundscheck(False)
@wraparound(False)
cdef np.ndarray contains_2d(double[:,:] pnt,
                            double[:,:] vertices,
                            long[:,:] simplices):
  '''
  Description
  -----------
    returns a boolean array identifying which points are contained in
    the closed simplicial complex described by vertices and simplices

  '''
  cdef:
    int count,i
    int N = pnt.shape[0]
    long[:] out = np.empty((N,),dtype=int,order='c') 
    segment2d *seg_array = <segment2d *>malloc(N*sizeof(segment2d))
    vector2d vec

  if not seg_array:
    raise MemoryError()

  try:
    vec = find_outside_2d(vertices)
    with nogil:
      for i in prange(N):
        seg_array[i].a.x = vec.x
        seg_array[i].a.y = vec.y
        seg_array[i].b.x = pnt[i,0]
        seg_array[i].b.y = pnt[i,1]
        count = _cross_count_2d(seg_array[i],vertices,simplices)
        out[i] = count%2

  finally:
    free(seg_array)

  return np.asarray(out,dtype=bool)


@boundscheck(False)
@wraparound(False)
@cdivision(True)
cdef bint is_intersecting_3d(segment3d seg,
                             triangle3d tri) nogil:
  '''
  Description
  ----------- 
    returns True if the 3D segment intersects the 3D triangle. An
    intersection is detected if the segment and triangle are not
    coplanar and if any part of the segment touches the triangle at an
    edge or in the interior. Intersections at corners are not detected

  Note
  ----
    This function determines where the segment intersects the plane
    containing the triangle and then projects the intersection point
    and triangle into 2D where a point in polygon test is
    performed. Although rare, 2D point in polygon tests can fail if
    the randomly determined outside point and the test point cross a
    vertex of the polygon. 
  '''
  cdef:
    vector3d dummy_pnt1,dummy_pnt2
    segment2d dummy_seg1,dummy_seg2,dummy_seg3,dummy_seg4
    double proj1,proj2,n1,n2,n3
    unsigned int i,idx1,idx2
    unsigned int count = 0

  # find point which is definitively outside of the triangle when
  # viewed from either the x, y, or z axis 
  dummy_pnt2.x = (min3(tri.a.x,tri.b.x,tri.c.x) - 
                  1.23456789)# + rand()*1.0/RAND_MAX)
  dummy_pnt2.y = (min3(tri.a.y,tri.b.y,tri.c.y) - 
                  2.34567891)# + rand()*1.0/RAND_MAX)
  dummy_pnt2.z = (min3(tri.a.z,tri.b.z,tri.c.z) - 
                  3.45678912)# + rand()*1.0/RAND_MAX)

  # find triangle normal vector components
  n1 =  ((tri.b.y-tri.a.y)*(tri.c.z-tri.a.z) - 
         (tri.b.z-tri.a.z)*(tri.c.y-tri.a.y))
  n2 = -((tri.b.x-tri.a.x)*(tri.c.z-tri.a.z) - 
         (tri.b.z-tri.a.z)*(tri.c.x-tri.a.x)) 
  n3 =  ((tri.b.x-tri.a.x)*(tri.c.y-tri.a.y) - 
         (tri.b.y-tri.a.y)*(tri.c.x-tri.a.x))

  proj1 = ((seg.a.x-tri.a.x)*n1 + 
           (seg.a.y-tri.a.y)*n2 +
           (seg.a.z-tri.a.z)*n3)
  proj2 = ((seg.b.x-tri.a.x)*n1 + 
           (seg.b.y-tri.a.y)*n2 +
           (seg.b.z-tri.a.z)*n3)

  if proj1*proj2 > 0:
    return False

  # coplanar segments will always return false
  # There is a possibility that the segment touches
  # one point on the triangle
  if (proj1 == 0) & (proj2 == 0):
    return False

  # intersection point
  dummy_pnt1.x = seg.a.x + (proj1/(proj1-proj2))*(
                  (seg.b.x-seg.a.x))
  dummy_pnt1.y = seg.a.y + (proj1/(proj1-proj2))*(
                  (seg.b.y-seg.a.y))
  dummy_pnt1.z = seg.a.z + (proj1/(proj1-proj2))*(
                  (seg.b.z-seg.a.z))

  if (fabs(n1) >= fabs(n2)) & (fabs(n1) >= fabs(n3)):
    dummy_seg1.a.x = dummy_pnt1.y
    dummy_seg1.a.y = dummy_pnt1.z
    dummy_seg1.b.x = dummy_pnt2.y
    dummy_seg1.b.y = dummy_pnt2.z

    dummy_seg2.a.x = tri.a.y
    dummy_seg2.a.y = tri.a.z
    dummy_seg2.b.x = tri.b.y
    dummy_seg2.b.y = tri.b.z

    dummy_seg3.a.x = tri.b.y
    dummy_seg3.a.y = tri.b.z
    dummy_seg3.b.x = tri.c.y
    dummy_seg3.b.y = tri.c.z

    dummy_seg4.a.x = tri.c.y
    dummy_seg4.a.y = tri.c.z
    dummy_seg4.b.x = tri.a.y
    dummy_seg4.b.y = tri.a.z

  elif (fabs(n2) >= fabs(n1)) & (fabs(n2) >= fabs(n3)):
    dummy_seg1.a.x = dummy_pnt1.x
    dummy_seg1.a.y = dummy_pnt1.z
    dummy_seg1.b.x = dummy_pnt2.x
    dummy_seg1.b.y = dummy_pnt2.z

    dummy_seg2.a.x = tri.a.x
    dummy_seg2.a.y = tri.a.z
    dummy_seg2.b.x = tri.b.x
    dummy_seg2.b.y = tri.b.z

    dummy_seg3.a.x = tri.b.x
    dummy_seg3.a.y = tri.b.z
    dummy_seg3.b.x = tri.c.x
    dummy_seg3.b.y = tri.c.z

    dummy_seg4.a.x = tri.c.x
    dummy_seg4.a.y = tri.c.z
    dummy_seg4.b.x = tri.a.x
    dummy_seg4.b.y = tri.a.z

  elif (fabs(n3) >= fabs(n1)) & (fabs(n3) >= fabs(n2)):
    dummy_seg1.a.x = dummy_pnt1.x
    dummy_seg1.a.y = dummy_pnt1.y
    dummy_seg1.b.x = dummy_pnt2.x
    dummy_seg1.b.y = dummy_pnt2.y

    dummy_seg2.a.x = tri.a.x
    dummy_seg2.a.y = tri.a.y
    dummy_seg2.b.x = tri.b.x
    dummy_seg2.b.y = tri.b.y

    dummy_seg3.a.x = tri.b.x
    dummy_seg3.a.y = tri.b.y
    dummy_seg3.b.x = tri.c.x
    dummy_seg3.b.y = tri.c.y

    dummy_seg4.a.x = tri.c.x
    dummy_seg4.a.y = tri.c.y
    dummy_seg4.b.x = tri.a.x
    dummy_seg4.b.y = tri.a.y


  if is_intersecting_2d(dummy_seg1,dummy_seg2):
    count += 1


  if is_intersecting_2d(dummy_seg1,dummy_seg3):
    count += 1


  if is_intersecting_2d(dummy_seg1,dummy_seg4):
    count += 1

  return count%2 == 1


@boundscheck(False)
@wraparound(False)
cdef np.ndarray cross_count_3d(double[:,:] start_pnts,
                               double[:,:] end_pnts,                         
                               double[:,:] vertices,
                               long[:,:] simplices):
  '''
  Description
  -----------
    returns an array of the number of intersections between each line
    segment, described by start_pnts and end_pnts, and the simplices

  '''
  cdef:
    int i
    int N = start_pnts.shape[0]
    long[:] out = np.empty((N,),dtype=int,order='c')
    segment3d *seg_array = <segment3d *>malloc(N*sizeof(segment3d))

  if not seg_array:
    raise MemoryError()

  try:
    with nogil:
      for i in prange(N):
        seg_array[i].a.x = start_pnts[i,0]
        seg_array[i].a.y = start_pnts[i,1]
        seg_array[i].a.z = start_pnts[i,2]
        seg_array[i].b.x = end_pnts[i,0]
        seg_array[i].b.y = end_pnts[i,1]
        seg_array[i].b.z = end_pnts[i,2]
        out[i] = _cross_count_3d(seg_array[i],vertices,simplices)
    
  finally:
    free(seg_array)

  return np.asarray(out)  


@boundscheck(False)
@wraparound(False)
cdef int _cross_count_3d(segment3d seg,
                         double[:,:] vertices,
                         long[:,:] simplices) nogil:
  cdef:
    unsigned int i
    unsigned int count = 0
    triangle3d tri

  for i in range(simplices.shape[0]):
    tri.a.x = vertices[simplices[i,0],0]
    tri.a.y = vertices[simplices[i,0],1]
    tri.a.z = vertices[simplices[i,0],2]
    tri.b.x = vertices[simplices[i,1],0]
    tri.b.y = vertices[simplices[i,1],1]
    tri.b.z = vertices[simplices[i,1],2]
    tri.c.x = vertices[simplices[i,2],0]
    tri.c.y = vertices[simplices[i,2],1]
    tri.c.z = vertices[simplices[i,2],2]
    if is_intersecting_3d(seg,tri):
      count += 1

  return count


@boundscheck(False)
@wraparound(False)
cdef np.ndarray cross_which_3d(double[:,:] start_pnts,
                               double[:,:] end_pnts,                         
                               double[:,:] vertices,
                               long[:,:] simplices):
  '''
  Description
  -----------
    returns an array identifying which simplex is intersected by
    start_pnts and end_pnts. 

  Note
  ----
    if there is no intersection then a ValueError is returned.

  '''  

  cdef:
    int i
    int N = start_pnts.shape[0]
    long[:] out = np.empty((N,),dtype=int,order='c')
    segment3d *seg_array = <segment3d *>malloc(N*sizeof(segment3d))

  if not seg_array:
    raise MemoryError()

  try:
    for i in range(N):
      seg_array[i].a.x = start_pnts[i,0]
      seg_array[i].a.y = start_pnts[i,1]
      seg_array[i].a.z = start_pnts[i,2]
      seg_array[i].b.x = end_pnts[i,0]
      seg_array[i].b.y = end_pnts[i,1]
      seg_array[i].b.z = end_pnts[i,2]
      out[i] = _cross_which_3d(seg_array[i],vertices,simplices)
    
  finally:
    free(seg_array)

  return np.asarray(out)  


@boundscheck(False)
@wraparound(False)
cdef int _cross_which_3d(segment3d seg,
                         double[:,:] vertices,
                         long[:,:] simplices) except *:         
  cdef:
    int i
    int N = simplices.shape[0]
    triangle3d tri
    
  for i in range(N):
    tri.a.x = vertices[simplices[i,0],0]
    tri.a.y = vertices[simplices[i,0],1]
    tri.a.z = vertices[simplices[i,0],2]
    tri.b.x = vertices[simplices[i,1],0]
    tri.b.y = vertices[simplices[i,1],1]
    tri.b.z = vertices[simplices[i,1],2]
    tri.c.x = vertices[simplices[i,2],0]
    tri.c.y = vertices[simplices[i,2],1]
    tri.c.z = vertices[simplices[i,2],2]
    if is_intersecting_3d(seg,tri):
      return i
 
  raise ValueError('No intersection found for segment [[%s,%s,%s],[%s,%s,%s]]' % 
                   (seg.a.x,seg.a.y,seg.a.z,seg.b.x,seg.b.y,seg.b.z))

@boundscheck(False)
@wraparound(False)
cdef np.ndarray cross_where_3d(double[:,:] start_pnts,
                               double[:,:] end_pnts,
                               double[:,:] vertices,
                               long[:,:] simplices):         
  '''
  Description
  -----------
    returns the intersection points between the line segments,
    described by start_pnts and end_pnts, and the simplices

  Note
  ----
    if there is no intersection then a ValueError is returned.

  '''
  cdef:
    int i
    int N = start_pnts.shape[0]
    double[:,:] out = np.empty((N,3),dtype=float,order='c')
    vector3d vec
    segment3d *seg_array = <segment3d *>malloc(N*sizeof(segment3d))

  if not seg_array:
    raise MemoryError()

  try:
    for i in range(N):
      seg_array[i].a.x = start_pnts[i,0]
      seg_array[i].a.y = start_pnts[i,1]
      seg_array[i].a.z = start_pnts[i,2]
      seg_array[i].b.x = end_pnts[i,0]
      seg_array[i].b.y = end_pnts[i,1]
      seg_array[i].b.z = end_pnts[i,2]
      vec = _cross_where_3d(seg_array[i],vertices,simplices)
      out[i,0] = vec.x
      out[i,1] = vec.y
      out[i,2] = vec.z

  finally:
    free(seg_array)

  return np.asarray(out)


@boundscheck(False)
@wraparound(False)
@cdivision(True)
cdef vector3d _cross_where_3d(segment3d seg,
                              double[:,:] vertices,
                              long[:,:] simplices) except *:         
  cdef:
    double proj1,proj2
    int idx
    vector3d norm
    triangle3d tri
    vector3d out 

  idx = _cross_which_3d(seg,vertices,simplices)
  tri.a.x = vertices[simplices[idx,0],0]
  tri.a.y = vertices[simplices[idx,0],1]
  tri.a.z = vertices[simplices[idx,0],2]
  tri.b.x = vertices[simplices[idx,1],0]
  tri.b.y = vertices[simplices[idx,1],1]
  tri.b.z = vertices[simplices[idx,1],2]
  tri.c.x = vertices[simplices[idx,2],0]
  tri.c.y = vertices[simplices[idx,2],1]
  tri.c.z = vertices[simplices[idx,2],2]

  norm.x =  ((tri.b.y-tri.a.y)*(tri.c.z-tri.a.z) -
             (tri.b.z-tri.a.z)*(tri.c.y-tri.a.y))
  norm.y = -((tri.b.x-tri.a.x)*(tri.c.z-tri.a.z) -
             (tri.b.z-tri.a.z)*(tri.c.x-tri.a.x))
  norm.z =  ((tri.b.x-tri.a.x)*(tri.c.y-tri.a.y) -
             (tri.b.y-tri.a.y)*(tri.c.x-tri.a.x))
  proj1 = ((seg.a.x-tri.a.x)*norm.x +
           (seg.a.y-tri.a.y)*norm.y +
           (seg.a.z-tri.a.z)*norm.z)
  proj2 = ((seg.b.x-tri.a.x)*norm.x +
           (seg.b.y-tri.a.y)*norm.y +
           (seg.b.z-tri.a.z)*norm.z)
  out.x = seg.a.x + (proj1/(proj1-proj2))*(
          (seg.b.x-seg.a.x))
  out.y = seg.a.y + (proj1/(proj1-proj2))*(
          (seg.b.y-seg.a.y))
  out.z = seg.a.z + (proj1/(proj1-proj2))*(
          (seg.b.z-seg.a.z))

  return out


@boundscheck(False)
@wraparound(False)
cdef np.ndarray cross_normals_3d(double[:,:] start_pnts,
                                 double[:,:] end_pnts,
                                 double[:,:] vertices,
                                 long[:,:] simplices):
  '''
  Description
  -----------
    returns the normal vectors to the simplices intersected start_pnts
    and end_pnts

  Note
  ----
    if there is no intersection then a ValueError is returned.

  '''

  cdef:
    int i
    int N = start_pnts.shape[0]
    double[:,:] out = np.empty((N,3),dtype=float,order='c')
    segment3d *seg_array = <segment3d *>malloc(N*sizeof(segment3d))
    vector3d vec

  if not seg_array:
    raise MemoryError()

  try:
    for i in range(N):
      seg_array[i].a.x = start_pnts[i,0]
      seg_array[i].a.y = start_pnts[i,1]
      seg_array[i].a.z = start_pnts[i,2]
      seg_array[i].b.x = end_pnts[i,0]
      seg_array[i].b.y = end_pnts[i,1]
      seg_array[i].b.z = end_pnts[i,2]
      vec = _cross_normals_3d(seg_array[i],vertices,simplices)
      out[i,0] = vec.x
      out[i,1] = vec.y
      out[i,2] = vec.z

  finally:
    free(seg_array)

  return np.asarray(out)


@boundscheck(False)
@wraparound(False)
@cdivision(True)
cdef vector3d _cross_normals_3d(segment3d seg,
                                double[:,:] vertices,
                                long[:,:] simplices) except *:         

  cdef:
    double proj,n
    int idx
    triangle3d tri
    vector3d out

  idx = _cross_which_3d(seg,vertices,simplices)
  tri.a.x = vertices[simplices[idx,0],0]
  tri.a.y = vertices[simplices[idx,0],1]
  tri.a.z = vertices[simplices[idx,0],2]
  tri.b.x = vertices[simplices[idx,1],0]
  tri.b.y = vertices[simplices[idx,1],1]
  tri.b.z = vertices[simplices[idx,1],2]
  tri.c.x = vertices[simplices[idx,2],0]
  tri.c.y = vertices[simplices[idx,2],1]
  tri.c.z = vertices[simplices[idx,2],2]

  out.x =  ((tri.b.y-tri.a.y)*(tri.c.z-tri.a.z) -
            (tri.b.z-tri.a.z)*(tri.c.y-tri.a.y))
  out.y = -((tri.b.x-tri.a.x)*(tri.c.z-tri.a.z) -
            (tri.b.z-tri.a.z)*(tri.c.x-tri.a.x))
  out.z =  ((tri.b.x-tri.a.x)*(tri.c.y-tri.a.y) -
            (tri.b.y-tri.a.y)*(tri.c.x-tri.a.x))
  proj = ((seg.b.x-tri.a.x)*out.x +
          (seg.b.y-tri.a.y)*out.y +
          (seg.b.z-tri.a.z)*out.z)

  if proj <= 0:
    out.x *= -1
    out.y *= -1
    out.z *= -1

  n = sqrt(out.x**2 + out.y**2 + out.z**2)
  out.x /= n
  out.y /= n
  out.z /= n

  return out


@boundscheck(False)
@wraparound(False)
cdef np.ndarray contains_3d(double[:,:] pnt,
                            double[:,:] vertices,
                            long[:,:] simplices):
  '''
  Description
  -----------
    returns a boolean array identifying whether the points are
    contained within the closed simplicial complex described by
    vertices and simplices

  '''
  cdef:
    int count,i
    int N = pnt.shape[0]
    long[:] out = np.empty((N,),dtype=int,order='c') 
    segment3d *seg_array = <segment3d *>malloc(N*sizeof(segment3d))
    vector3d vec

  if not seg_array:
    raise MemoryError()

  try:
    vec = find_outside_3d(vertices)
    with nogil:
      for i in prange(N):
        seg_array[i].a.x = vec.x
        seg_array[i].a.y = vec.y
        seg_array[i].a.z = vec.z
        seg_array[i].b.x = pnt[i,0]
        seg_array[i].b.y = pnt[i,1]
        seg_array[i].b.z = pnt[i,2]
        count = _cross_count_3d(seg_array[i],vertices,simplices)
        out[i] = count%2

  finally:
    free(seg_array)

  return np.asarray(out,dtype=bool)


def normal(M):
  '''
  Description
  -----------
    returns the normal vector to the D-1 vectors in D dimensional
    space
                                     
  Parameters
  ----------                 
    M: (D-1,D) array of vectors  
                           
  Note
  ----
    supports broadcasting

  '''
  N = M.shape[-1]
  Msubs = [np.delete(M,i,-1) for i in range(N)]
  out = np.linalg.det(Msubs)
  out[1::2] *= -1
  out = np.rollaxis(out,-1)
  out /= np.linalg.norm(out,axis=-1)[...,None]
  return out


def complex_intersection(start_points,end_points,vertices,simplices):
  '''
  Description
  -----------
    returns the intersection points between the line segments,
    described by start_points and end_points, and the simplicial
    complex, described by vertices and simplices. This function works
    for 1, 2, and 3 spatial dimensions.

  Parameters
  ----------
    start_points: (N,D) array of vertices describing one end of each
      line segment. N is the number of line segments

    end_points: (N,D) array of vertices describing the other end of
      each line segment. N is the number of line segments.

    vertices: (M,D) array of vertices within the simplicial complex. M
      is the number of vertices

    simplices: (P,D) array of vertex indices for each simplex. P is
      the number of simplices

  Returns
  -------
    out: (N,D) array of intersection points    

  Note
  ----
    This function fails when a intersection is not found for a line
    segment

  '''
  start_points = np.asarray(start_points)
  end_points = np.asarray(end_points)
  vertices = np.asarray(vertices)
  simplices = np.asarray(simplices)
  assert start_points.shape[1] == end_points.shape[1]
  assert start_points.shape[1] == vertices.shape[1]
  assert start_points.shape[0] == end_points.shape[0]
  dim = start_points.shape[1]
  if dim == 1:
    vert = vertices[simplices[:,0]]
    crossed_bool = (start_points-vert.T)*(end_points-vert.T) <= 0.0
    crossed_idx = np.array([np.nonzero(i)[0][0] for i in crossed_bool],dtype=int)
    out = vert[crossed_idx]

  if dim == 2:
    out = cross_where_2d(start_points,end_points,vertices,simplices)

  if dim == 3:
    out = cross_where_3d(start_points,end_points,vertices,simplices)

  return out


def complex_normal(start_points,end_points,vertices,simplices):
  '''
  Description
  -----------
    returns the normal vectors to the simplexes intersected by the
    line segments, described by start_points and end_points. This
    function works for 1, 2, and 3 spatial dimensions.

  Parameters
  ----------
    start_points: (N,D) array of vertices describing one end of each
      line segment. N is the number of line segments

    end_points: (N,D) array of vertices describing the other end of
      each line segment. N is the number of line segments.

    vertices: (M,D) array of vertices within the simplicial complex. M
      is the number of vertices

    simplices: (P,D) array of vertex indices for each simplex. P is
      the number of simplices

  Returns
  -------
    out: (N,D) array of normal vectors

  Note
  ----
    This function fails when a intersection is not found for a line
    segment

  '''
  start_points = np.asarray(start_points)
  end_points = np.asarray(end_points)
  vertices = np.asarray(vertices)
  simplices = np.asarray(simplices)
  assert start_points.shape[1] == end_points.shape[1]
  assert start_points.shape[1] == vertices.shape[1]
  assert start_points.shape[0] == end_points.shape[0]
  dim = start_points.shape[1]
  if dim == 1:
    out = np.ones(start_points.shape,dtype=float)
    vert = vertices[simplices[:,0]]
    crossed_bool = (start_points-vert.T)*(end_points-vert.T) <= 0.0
    crossed_idx = np.array([np.nonzero(i)[0][0] for i in crossed_bool],dtype=int)
    crossed_vert = vert[crossed_idx]
    out[crossed_vert < start_points] = -1.0

  if dim == 2:
    out = cross_normals_2d(start_points,end_points,vertices,simplices)

  if dim == 3:
    out = cross_normals_3d(start_points,end_points,vertices,simplices)

  return out


def complex_group(start_points,end_points,vertices,simplices,group):
  '''
  Description
  -----------
    returns the group number of the simplex intersected by the line
    segments, described by start_points and end_points. This function
    works for 1, 2, and 3 spatial dimensions. 

  Parameters
  ----------
    start_points: (N,D) array of vertices describing one end of each
      line segment. N is the number of line segments

    end_points: (N,D) array of vertices describing the other end of
      each line segment. N is the number of line segments.

    vertices: (M,D) array of vertices within the simplicial complex. M
      is the number of vertices

    simplices: (P,D) array of vertex indices for each simplex. P is
      the number of simplices
    
    group: (P,) array of integer group IDs for each simplex. 

  Returns
  -------
    out: (N,) array of group IDs

  Note
  ----
    This function fails when a intersection is not found for a line
    segment

  '''
  start_points = np.asarray(start_points,dtype=float)
  end_points = np.asarray(end_points,dtype=float)
  vertices = np.asarray(vertices,dtype=float)
  simplices = np.asarray(simplices,dtype=int)
  group = np.asarray(group,dtype=int)
  assert start_points.shape[1] == end_points.shape[1]
  assert start_points.shape[1] == vertices.shape[1]
  assert start_points.shape[0] == end_points.shape[0]
  dim = start_points.shape[1]
  if dim == 1:
    out = np.ones(start_points.shape,dtype=float)
    vert = vertices[simplices[:,0]]
    crossed_bool = (start_points-vert.T)*(end_points-vert.T) <= 0.0
    smp_ids = np.array([np.nonzero(i)[0][0] for i in crossed_bool],dtype=int)

  if dim == 2:
    smp_ids = cross_which_2d(start_points,end_points,vertices,simplices)

  if dim == 3:
    smp_ids= cross_which_3d(start_points,end_points,vertices,simplices)

  out = np.array(group[smp_ids],copy=True)
  return out


def complex_cross_count(start_points,end_points,vertices,simplices):
  '''
  Description
  -----------
    returns the number of simplexes crossed by the line segments
    described by start_points and end_points. This function works for
    1, 2, and 3 spatial dimensions.

  Parameters
  ----------
    start_points: (N,D) array of vertices describing one end of each
      line segment. N is the number of line segments

    end_points: (N,D) array of vertices describing the other end of
      each line segment. N is the number of line segments.

    vertices: (M,D) array of vertices within the simplicial complex. M
      is the number of vertices

    simplices: (P,D) array of vertex indices for each simplex. P is
      the number of simplices

  Returns
  -------
    out: (N,) array of intersection counts

  '''
  start_points = np.asarray(start_points,dtype=float)
  end_points = np.asarray(end_points,dtype=float)
  vertices = np.asarray(vertices,dtype=float)
  simplices = np.asarray(simplices,dtype=int)
  assert start_points.shape[1] == end_points.shape[1]
  assert start_points.shape[1] == vertices.shape[1]
  assert start_points.shape[0] == end_points.shape[0]
  dim = start_points.shape[1]
  if dim == 1:
    vert = vertices[simplices[:,0]]
    crossed_bool = (start_points-vert.T)*(end_points-vert.T) <= 0.0
    out = np.sum(crossed_bool,axis=1)

  if dim == 2:
    out = cross_count_2d(start_points,end_points,vertices,simplices)

  if dim == 3:
    out = cross_count_3d(start_points,end_points,vertices,simplices)

  return out


def complex_contains(points,vertices,simplices):
  '''
  Description
  -----------
    returns a boolean array identifying whether the points are
    contained within a closed simplicial complex described by vertices
    and simplices.  This function works for 1, 2, and 3 spatial
    dimensions.

  Parameters
  ----------
    points: (N,D) array of points

    vertices: (M,D) array of vertices within the simplicial complex. M
      is the number of vertices

    simplices: (P,D) array of vertex indices for each simplex. P is
      the number of simplices

  Returns
  -------
    out: (N,) boolean array identifying whether each point is in the
      simplicial complex

  Note
  ----
    This function does not ensure that the simplicial complex is
    closed.  If it is not then bogus results will be returned.  The
    closedness can be checked using the is_valid function.  

    
    This function determines whether a point is contained within the
    simplicial complex by finding the number of intersections between
    each point and an arbitrary outside point.  It is possible,
    although rare, that this function will fail if the line segment
    intersects a simplex at an edge.

  '''
  points = np.asarray(points)
  vertices = np.asarray(vertices)
  simplices = np.asarray(simplices)
  dim = points.shape[1]
  assert points.shape[1] == vertices.shape[1]
  if dim == 1:
    vert = vertices[simplices[:,0]]
    end_points = np.ones(np.shape(points))*np.min(vertices) - 1.0
    crossed_bool = (points-vert.T)*(end_points-vert.T) <= 0.0
    crossed_count = np.sum(crossed_bool,axis=1)
    out = np.array(crossed_count%2,dtype=bool)

  if dim == 2:
    out = contains_2d(points,vertices,simplices)

  if dim == 3:
    out = contains_3d(points,vertices,simplices)

  return out



def contains_N_duplicates(iterable,N=1):
  '''            
  returns True if every element in iterable is repeated N times
  '''
  for s in iterable:
    count = 0
    for t in iterable:
      # s == t can either return a boolean, or a boolean array in the
      # event of s and t being numpy arrays.  np.all returns the 
      # appropriate value in either case
      if np.all(s == t):
        count += 1

    if count != N:
      return False

  return True


def is_valid(smp):
  '''             
  Description
  -----------
    Returns True if the following conditions are met:

      every simplex is unique

      every simplex contains unique vertices

      (for 2D and 3D) every simplex shares an edge with exactly one 
      other simplex. (for 1D) exactly 2 simplexes are given                     

  Parameters
  ----------
    smp: simplices defining the domain

  Note
  ----
    This function can take a while for a large (>1000) number of 
    simplexes 

  '''
  smp = np.asarray(smp)
  smp = np.array([np.sort(i) for i in smp])
  dim = smp.shape[1]
  sub_smp = []
  # check for repeated simplexes 
  if not contains_N_duplicates(smp,1):
    return False

  for s in smp:
    # check for repeated vertices in a simplex
    if not contains_N_duplicates(s,1):
      return False

    for c in combinations(s,dim-1):
      c_list = list(c)
      c_list.sort()
      sub_smp.append(c_list)

  return contains_N_duplicates(sub_smp,2)





