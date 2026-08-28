
function [new_bias]=update_biases(year,day, data_label, varargin);

global file_info par_info return_flag
global yesterday

init_par_info;
init_file_info;

bias_smoothing_factor = par_info.bias_smoothing_factor; %45, odd-sized window/convolution kernael is symmetrically centred on a grid cell
bias_weighting_factor = par_info.bias_weighting_factor; % [0.4, 0.6]
bad_val               = par_info.bad_val;
tenth_or_twentieth    = par_info.tenth_or_twentieth;

return_flag=1;

% Check processing direction to ensure the correct reference SST is used.
% Normally this is set to one, and the reference day is the day previous
% to the one in question. However if direction is -1, the day chronologically
% afterwards is used. Other values may also be specified. For example, if 
% direction is set to 7, the reference biases from 7 days ago will be used.
% 
if (length(varargin) >0)
   direction=varargin{1}(1);
else
   direction=1;
end


% Determine string for date in yyyy_ddd format from input year and day of year,
% where yyyy is year, and ddd is day of year.
% For example, day 36 of year 2004 is specified with the string "2004_036".
% Also get string for previous day, as various datafiles from the previous day will
% be required.

today=get_datestring(year,day);
yesterday=get_datestring(year,day-direction);


% Get information about file locations and names and parameters.

init_file_info;
init_par_info;

spatial_resolution = par_info.spatial_resolution;
cells_per_degree= par_info.cells_per_degree; % 1/20=0.05º

% Use global file_info structure as defined by init_file_info.m to 
% determine information about directories and filename.

dir_analysis             = file_info.dir_analysis;
dir_ancillary            = file_info.dir_ancillary;
dir_input_ssts           = file_info.dir_input_ssts;
name_sst_biases          = file_info.name_sst_biases;
name_sst_analysis        = file_info.name_sst_analysis;
name_ice_mask            = file_info.name_ice_mask;
name_land_mask           = file_info.name_land_mask;

eval(['load  ' dir_analysis name_sst_biases yesterday ]) % used for eval(['old_bias=' data_label 'bias;'])

% Now bias-correct w.r.t. OSTIA (not analysis) to alleviate drift problem
  
disp(['loading ostia ice land']) %RILEY
eval(['load  ' dir_analysis 'ostia_' tenth_or_twentieth today]) %load all variables stored inside this .mat file (may include "sst" used below)
sst_analysis = sst;
eval(['load  ' dir_analysis name_ice_mask today ' ice_mask'])
eval(['load  ' dir_ancillary name_land_mask  ' land_mask'])
ice=find(ice_mask>0);
land=find(land_mask==0);

eval(['old_bias=' data_label 'bias;'])
disp(['old_bias=' data_label 'bias;']) %RILEY
disp(data_label) %RILEY

data_file=[dir_input_ssts data_label today '.mat'];
fid=fopen(data_file,'r');

if (fid>0)
   fclose(fid);
   eval(['load  ' dir_input_ssts data_label today ' sst' ])

   if ~(size(sst) == [spatial_resolution])
      global_sst=NaN*ones(spatial_resolution);
      eval(['load  ' dir_input_ssts data_label today ' pixel_extent' ])
  
      cpd=cells_per_degree;
      mylimits=[(48*cpd+1):(132*cpd), (290*cpd+1):(360*cpd)];
      mystr=sprintf('(%d:%d, %d:%d)', mylimits);
  
      if(strcmp(pixel_extent, mystr))      
      disp([pixel_extent 'is pixelextent']) %RILEY
      %if(strcmp(pixel_extent,'(481:1320, 2901:3600)'))
         sst=sst(:,1:70*cpd);
      end
      eval(['global_sst' pixel_extent '=sst;'])
      sst=global_sst; 
   end


   old_bias(land)=NaN;
   old_bias(ice)=NaN;
   % OSTIA - input sst
   obs_bias=sst_analysis-sst;  
   % Maturi et al. 2017 p.5 Bias corrections.
   wt_new_bias=weighted_average(old_bias, obs_bias, ...
                                bias_weighting_factor(1), bias_weighting_factor(2), bad_val);
   new_bias=smooth_analysis(wt_new_bias,bias_smoothing_factor);

   bad=find(isnan(new_bias));
   new_bias(bad)=0;
   new_bias(land)=NaN;
   bad=find(new_bias==0);
  
   bias=new_bias;

   eval(['save  ' dir_input_ssts data_label today ' bias -append'])
 
   

else
   new_bias=old_bias;
   
end

