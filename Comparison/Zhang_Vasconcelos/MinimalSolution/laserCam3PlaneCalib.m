% Minimal algorithm for registration of 3 co-linear lines and 3 planes
%
% INPUT:
%   PIcam - 4x3 matrix with columns defining each plane
%   L     - 6x3 matrix with co-planar lines in plucker coordinates
%           NOTE: the lines MUST lie in the plane z=10 for this function to
%           work properly. If this is not the case, no errors are 
%           displayed, but the output will be wrong
%   disp  - debug flag
%
% OUTPUT:
%   T - 4x4 matrix with the transformation from the planes reference frame 
%       to the lines reference frame
%

function T = laserCam3PlaneCalib(PIcam, L,disp)

if ~exist('disp','var')
    disp=0;
end

Tlrs = eye(4);
Tlrs(3,4) = 10; 

% dual space
X(:,1) = PluckerDual(L(:,1));
X(:,2) = PluckerDual(L(:,2));
X(:,3) = PluckerDual(L(:,3));

% rotation
xl    = X(1:3,:);
xcam  = PIcam(1:3,:);
Delta = [Tlrs(1:3,3); Tlrs(1:3,3).'*Tlrs(1:3,4)];
b     = Delta(1:3)*sign(Delta(4));
R     = rotation3Pt(xl, xcam, b, disp);

% translation
T = nan(4,4,size(R,3));
for i=1:size(R,3)
    PIr = [R(:,:,i).' [0;0;0]; 0 0 0 1] * PIcam;
    v = PIr(1:3,:) ./ (ones(3,1)*PIr(3,:)); 
    M = [v; zeros(3,3)];
    PIl(1:3,1) = PluckerLineLineIntersection(X(:,1), M(:,1));
    PIl(1:3,2) = PluckerLineLineIntersection(X(:,2), M(:,2));
    PIl(1:3,3) = PluckerLineLineIntersection(X(:,3), M(:,3));
    PIl(4,:) = 1;
    
    nl = PIl(1:3,:);
    nr = PIr(1:3,:);
    A(1:9,1:4) = [-nl(:,1)*(nr(:,1).') nl(:,1)-nr(:,1); ...
                    -nl(:,2)*(nr(:,2).') nl(:,2)-nr(:,2); ...
                    -nl(:,3)*(nr(:,3).') nl(:,3)-nr(:,3)];   
    [U, S, V] = svd(A);
    T(:,:,i) = [R(:,:,i).' V(1:3,end)/V(end,end); 0 0 0 1];   
end


