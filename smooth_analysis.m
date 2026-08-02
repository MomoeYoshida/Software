function [outarray]=smooth_analysis(inarray, smooth_factor);
warning off
% Turn land flag (-999) into Nan.
land=find(inarray==-999);
inarray(land)=NaN;

land=find(isnan(inarray));
% smooths data array. 

a=inarray;

% Create a mask for valid pixels.
i=1-isnan(inarray); % valide pixel > 1, NaN pixel > 0
an=a;
an(find(isnan(a)))=0; % replace NaNs with 0 for convolution

% Smoothing
% 1. Sum all SST values inside each smooth_factor x smooth_factor window.
% 2. Count the number of valid pixels in that winddow.
% as: Replace by the smoothed/averaged/mean value at each centre pixel of that window
% Moves over every pixel
as = conv2(an,ones(smooth_factor),'same')./conv2(i,ones(smooth_factor),'same');

if(length(land)>0)

   as(land)=NaN;
end

outarray=as;
