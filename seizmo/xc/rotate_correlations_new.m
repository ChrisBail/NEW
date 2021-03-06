function [xc]=rotate_correlations_new(xc,to)
%ROTATE_CORRELATIONS_NEW    Rotates horizontal correlations to N/E or R/T
%
%    Usage:    xc=rotate_correlations_new(xc,to)
%
%    Description:
%     XC=ROTATE_CORRELATIONS_NEW(XC,TO) rotates horizontal correlogram sets
%     in SEIZMO struct XC to the orientation specified by TO.  TO may be
%     either:
%      'NE' - rotates correlogram sets to North & East
%      'RT' - rotates correlogram sets to pairwise Radial & Transverse
%     The output dataset will not be reordered but will have records
%     removed that do not belong to a set.  This function is only
%     compatible with correlograms generated by CORRELATE due to header
%     field arrangement (so you need to mimic that to use this function).
%
%    Notes:
%     - This is an expansion of the algorithm published in:
%        Lin, Moschetti, & Ritzwoller 2008, GJI,
%         doi: 10.1111/j.1365-246X.2008.03720.x
%     - Currently requires each set to have the same number of points,
%       the same sample rate and the same starting lag time.
%     - The .name fields are altered to match the header info.
%
%    Header changes:
%     Master & Slave Fields may be switched (see REVERSE_CORRELATIONS).
%     KCMPNM & KT3 are changed to end with R/T or N/E.
%     CMPAZ & USER3 are updated to reflect the component azimuths.
%
%    Examples:
%     % Rotate, Correlate, Rotate:
%     data=rotate(data,'to',0,'kcmpnm1','N','kcmpnm2','E');
%     xc=correlate(data,'mcxc');
%     xc=rotate_correlations_new(xc,'RT');
%
%    See also: HORZ_CORRELATION_SETS, CORRELATE, REVERSE_CORRELATIONS,
%              ISXC, SPLIT_AUTO_CORRELATIONS, NO_REDUNDANT_CORRELATIONS,
%              IS_FULL_MATRIX_OF_CORRELATIONS, NAME_CORRELATIONS, ROTATE

%     Version History:
%        June 10, 2010 - initial version
%        June 13, 2010 - major bugfix
%        June 17, 2010 - more checks for no rotatible records
%        July  2, 2010 - fix cat warnings (dumb Matlab feature)
%        Feb.  7, 2012 - update cmpaz/user3 fields (azimuths), doc update
%        Nov.  7, 2012 - rewrite based on split input/output
%        Jan. 28, 2013 - doc update
%        Sep.  9, 2013 - rewrite to do only single dataset io and autoxc
%        Sep. 20, 2013 - properly optimized checking, debugging
%
%     Written by Garrett Euler (ggeuler at wustl dot edu)
%     Last Updated Sep. 20, 2013 at 15:05 GMT

% todo:

% check nargin
error(nargchk(2,2,nargin));

% check structure
error(seizmocheck(xc,'dep'));

% turn off struct checking
oldseizmocheckstate=seizmocheck_state(false);

% safely check headers
try
    xc=checkheader(xc,...
        'MULCMP_DEP','ERROR',...
        'NONTIME_IFTYPE','ERROR',...
        'FALSE_LEVEN','ERROR',...
        'UNSET_ST_LATLON','ERROR',...
        'UNSET_EV_LATLON','ERROR');
    
    % turn off header checking
    oldcheckheaderstate=checkheader_state(false);
catch
    % toggle checking back
    seizmocheck_state(oldseizmocheckstate);
    
    % rethrow error
    error(lasterror);
end

% attempt rotation
try
    % verbosity
    verbose=seizmoverbose(false);
    
    % retrieve horizontal sets
    [in,set,cmp,rev]=horz_correlations_sets(xc);
    nsets=max(set);
    
    % check orientation option
    if(~ischar(to) || numel(to)~=2 || size(to,1)~=1 ...
            || ~any(strcmpi(to,{'rt' 'ne' 'tr' 'en'})))
        error('seizmo:rotate_correlations_new:badInput',...
            'TO msut be either ''RT'' or ''NE''!');
    end
    
    % reduce correlation dataset to those that matter here
    xc=xc(in);
    
    % return empty struct if none
    if(isempty(xc)); return; end
    
    % reverse correlograms as needed
    if(any(rev)); xc(rev)=reverse_correlations(xc(rev)); end
    
    % needed header info
    [maz,saz,mnm,snm,mi,si,az,gcp]=getheader(xc,'user3','cmpaz','kt',...
        'kname','user0','user1','az','gcp');
    mnmc=char(mnm(:,4));
    snmc=char(snm(:,4));
    
    % component code check
    if(size(mnmc,2)~=3 || size(snmc,2)~=3)
        error('seizmo:rotate_correlations_new:badHeader',...
            'KCMPNM & KT3 header fields of correlograms must be 3 chars!');
    end
    
    % detail message
    if(verbose)
        disp('Rotating Horizontal Correlogram Set(s)');
        print_time_left(0,nsets);
    end
    
    % loop over sets
    [depmin,depmax,depmen]=deal(nan(numel(xc),1));
    for i=1:nsets
        % rotation angles
        % - note: no consistency check for ev/st/az/gcp header fields
        c1=set==i & cmp==1;
        switch lower(to)
            case {'ne' 'en'}
                cc=cosd(-maz(c1))*cosd(-saz(c1));
                cs=cosd(-maz(c1))*sind(-saz(c1));
                sc=sind(-maz(c1))*cosd(-saz(c1));
                ss=sind(-maz(c1))*sind(-saz(c1));
            case {'rt' 'tr'}
                cc=cosd(az(c1)-maz(c1))*cosd(gcp(c1)-saz(c1));
                cs=cosd(az(c1)-maz(c1))*sind(gcp(c1)-saz(c1));
                sc=sind(az(c1)-maz(c1))*cosd(gcp(c1)-saz(c1));
                ss=sind(az(c1)-maz(c1))*sind(gcp(c1)-saz(c1));
        end
        
        % indices to this set's other correlograms
        c2=set==i & cmp==2;
        c3=set==i & cmp==3;
        c4=set==i & cmp==4;
        
        % rotate
        if(~any(c2)) % autoxc set missing NE/RT
            xc2=flipud(xc(c3).dep); % note: assumes autoxc is lag symmetric
            [xc(c1).dep,xc(c3).dep,xc(c4).dep]=deal(...
                xc(c1).dep*cc+xc2*cs+xc(c3).dep*sc+xc(c4).dep*ss,...
               -xc(c1).dep*sc-xc2*ss+xc(c3).dep*cc+xc(c4).dep*cs,...
                xc(c1).dep*ss-xc2*sc-xc(c3).dep*cs+xc(c4).dep*cc);
        elseif(~any(c3)) % autoxc set missing EN/TR
            xc3=flipud(xc(c2).dep); % note: assumes autoxc is lag symmetric
            [xc(c1).dep,xc(c2).dep,xc(c4).dep]=deal(...
                xc(c1).dep*cc+xc(c2).dep*cs+xc3*sc+xc(c4).dep*ss,...
               -xc(c1).dep*cs+xc(c2).dep*cc-xc3*ss+xc(c4).dep*sc,...
                xc(c1).dep*ss-xc(c2).dep*sc-xc3*cs+xc(c4).dep*cc);
        else % xc
            [xc(c1).dep,xc(c2).dep,xc(c3).dep,xc(c4).dep]=deal(...
                xc(c1).dep*cc+xc(c2).dep*cs+xc(c3).dep*sc+xc(c4).dep*ss,...
               -xc(c1).dep*cs+xc(c2).dep*cc-xc(c3).dep*ss+xc(c4).dep*sc,...
               -xc(c1).dep*sc-xc(c2).dep*ss+xc(c3).dep*cc+xc(c4).dep*cs,...
                xc(c1).dep*ss-xc(c2).dep*sc-xc(c3).dep*cs+xc(c4).dep*cc);
        end
        
        % update dep*
        if(numel(xc(c1).dep)>0)
            depmin(c1)=min(xc(c1).dep);
            depmax(c1)=max(xc(c1).dep);
            depmen(c1)=nanmean(xc(c1).dep);
            if(any(c2))
                depmin(c2)=min(xc(c2).dep);
                depmax(c2)=max(xc(c2).dep);
                depmen(c2)=nanmean(xc(c2).dep);
            end
            if(any(c3))
                depmin(c3)=min(xc(c3).dep);
                depmax(c3)=max(xc(c3).dep);
                depmen(c3)=nanmean(xc(c3).dep);
            end
            depmin(c4)=min(xc(c4).dep);
            depmax(c4)=max(xc(c4).dep);
            depmen(c4)=nanmean(xc(c4).dep);
        end
        
        % detail message
        if(verbose); print_time_left(i,nsets); end
    end
    
    % fix up component names & orientations
    %  1/ 2/ 3/ 4
    % NN/NE/EN/EE
    % RR/RT/TR/TT
    switch lower(to)
        case {'ne' 'en'}
            % orientations
            maz(:)=0;
            maz(cmp>2)=90;
            saz(:)=90;
            saz(mod(cmp,2)==1)=0;
            
            % names
            mnmc=strcat(mnmc(:,1:2),'N');
            mnmc(cmp>2,3)='E';
            snmc=strcat(snmc(:,1:2),'E');
            snmc(mod(cmp,2)==1,3)='N';
        case {'rt' 'tr'}
            % orientations
            taz=lonmod(az+90);
            tgcp=lonmod(gcp+90);
            maz(:)=az;
            maz(cmp>2)=taz(cmp>2);
            saz(:)=tgcp;
            saz(mod(cmp,2)==1)=gcp(mod(cmp,2)==1);
            
            % names
            mnmc=strcat(mnmc(:,1:2),'R');
            mnmc(cmp>2,3)='T';
            snmc=strcat(snmc(:,1:2),'T');
            snmc(mod(cmp,2)==1,3)='R';
    end
    
    % update headers
    xc=changeheader(xc,'depmin',depmin,'depmax',depmax,'depmen',depmen,...
        'cmpaz',saz,'user3',maz,'kcmpnm',snmc,'kt3',mnmc);
    
    % toggle verbosity back
    seizmoverbose(verbose);
    
    % toggle checking back
    seizmocheck_state(oldseizmocheckstate);
    checkheader_state(oldcheckheaderstate);
catch
    % toggle verbosity back
    seizmoverbose(verbose);
    
    % toggle checking back
    seizmocheck_state(oldseizmocheckstate);
    checkheader_state(oldcheckheaderstate);
    
    % rethrow error
    error(lasterror);
end

% update names
d=['%0' num2str(fix(log10(max([mi;si])))+1) 'd'];
name=strcat(...
    'CORR_-_MASTER_-_REC',num2str(mi,d),'_-_',mnm(:,1),'.',mnm(:,2),'.',...
    mnm(:,3),'.',mnmc,'_-_SLAVE_-_REC',num2str(si,d),'_-_',snm(:,1),'.',...
    snm(:,2),'.',snm(:,3),'.',snmc);
[xc.name]=deal(name{:});

end
