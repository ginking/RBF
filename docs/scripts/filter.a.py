''' 
The following demonstrates using *rbf.filter.filter* to remove noise 
from the classic Lena image. The image has been resampled into 100,000 
data points which are normally distributed about [0.5,0.5] and white 
noise has been added to each datum. *rbf.filter.filter* acts as a 
low-pass filter which damps out frequencies which are higher than the 
user specified cutoff frequency.  In this example the cutoff frequency 
is set to 40.
'''
import numpy as np
from scipy.misc import face
from scipy.interpolate import NearestNDInterpolator
import matplotlib.pyplot as plt
from rbf.filter import filter
np.random.seed(4)

x = np.linspace(0.0,1.0,768)
y = np.linspace(1.0,0.0,768)
x,y = np.meshgrid(x,y)
points = np.array([x.flatten(),y.flatten()]).T
values = np.linalg.norm(face(),axis=2)[:,256:].flatten()
#values = lena().flatten().astype(float)
values /= 441.7 # normalize so that the max is 1.0
signal = NearestNDInterpolator(points,values)

# interpolate Lena onto new observation points and add noise
points_obs = np.random.normal(0.5,0.3,(100000,2))
#points_obs = rbf.halton.halton(50000,2)  
u_obs = signal(points_obs) + np.random.normal(0.0,0.2,100000)
# find filtered solution
cutoff = 60.0
soln,_ = filter(points_obs,u_obs,cutoff=cutoff,n=20,samples=0)

# plot the observed and filtered results
fig,ax = plt.subplots(2,1,figsize=(6,10))
ax[0].set_aspect('equal')
ax[0].set_axis_bgcolor('blue')
ax[0].set_xlim((0,1))
ax[0].set_ylim((0,1))
ax[0].set_title('noisy data')
ax[1].set_aspect('equal')
ax[1].set_axis_bgcolor('blue')
ax[1].set_xlim((0,1))
ax[1].set_ylim((0,1))
ax[1].set_title(u'filtered solution $\mathregular{(\omega_c = %s)}$' % cutoff)
p1 = ax[0].scatter(points_obs[:,0],points_obs[:,1],s=4,c=u_obs,
                   edgecolor='none',cmap='Greys_r',vmin=-0.1,vmax=1.1)
plt.colorbar(p1,ax=ax[0])
p2 = ax[1].scatter(points_obs[:,0],points_obs[:,1],s=4,c=soln,
                   edgecolor='none',cmap='Greys_r',vmin=-0.1,vmax=1.1)
plt.colorbar(p2,ax=ax[1])
plt.tight_layout()
plt.savefig('../figures/filter.a.png')
plt.show()

