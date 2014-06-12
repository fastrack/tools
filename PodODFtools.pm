package PodODFtools ;

####-----------------------------------
### File	: PodODFtools.pm
### Author	: Ch.Minc
### Purpose	: set of tools translatePod into ODF, PDF , "HTML show"
### Version	: 1.11 12/06/2014 21:40:36
### copyright GNU license
### utf-8 àéè
####-----------------------------------

use  5.012003;

use strict ;
use warnings ;
use Moose;
use Carp ;
$Carp::Verbose='true' ;

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Data::Dumper;
use Pod::HtmlEasy 1.001009 ;
use ODF::lpOD 1.118 ;
use English qw( -no_match_vars ) ;

use File::Temp;
use Encode  qw (from_to decode_utf8 encode_utf8) ;
use Cwd  ;
use charnames ':full' ;

use HTML::Entities;

use Time::HiRes qw (gettimeofday tv_interval usleep); 
use POSIX qw(strftime);

our ($VERSION) = '$Revision: 1.11 $' =~ m{ \$Revision: \s+ (\S+) }xms;

# model file required for gmlf
has 'model' => (is => 'rw', isa => 'Str', required => 1);
# output odf file name format odf for a gmlf call
has 'gmlf'  => (is => 'rw', isa => 'Str', required => 0,default=>'./gmlf.odt');
# input pod file - ask to be in 'cp1252' for compatibility with package ODF::lpoD
has 'pod'   => (is => 'rw', isa => 'Str', required => 1);
# output base name for slides in HTML
has 'showfile'   => (is => 'rw', isa => 'Str', required => 1, default=>'./showpage');
# input pod character could be set in principle, see above
has 'pod_car'  =>  (is => 'rw', isa => 'Str',required => 0,default =>'cp1252');
# output character in ODF could be set too, 'cp1252 avoided problem, see above
has 'odf_car'  =>  (is => 'rw', isa => 'Str', required => 0,default =>'cp1252');
# thisisan internal parameter for swithing between normal and gmlf format
has 'made_for' =>(is => 'rw', isa => 'Str', required => 0,default =>'gmlf') ;
# this parameter resize the picture in ODF file by scaling them down
has 'scaledown' =>(is => 'rw', isa => 'Int', required => 0,default =>4) ;
# these parameters told where to find libreoffice/openoffice used for generating pdf files from odf ones
has 'soffice_dir' =>(is => 'rw', isa => 'ArrayRef[Str]', required => 0,default =>sub{["C:", 'Program Files', 'LibreOffice 4', 'program'] ;});
has 'soffice_exe' =>(is => 'rw', isa => 'Str', required => 0,default =>"swriter.exe");

# these regex  used to get the attributes of pictures in pod with the tag "=for html" 
has 'regex_for_html_style'=>(is=>'rw',
                  isa=>'RegexpRef',
                  default=>sub{qr/img\s*.*style=\"(?<style>.*)\"\.*/i});
		  
has 'regex_for_html_alt'=>(is=>'rw',
                  isa=>'RegexpRef',
                  default=>sub{qr/img\s*.*alt=\"(?<alt>.*)\"\s*.*/i});
		  
has 'regex_for_html_title'=>(is=>'rw',
                  isa=>'RegexpRef',
                  default=>sub{qr/img\s*.*title=\"(?<title>.*)\"\s*.*/i});		  

has 'regex_for_html_src'=>(is=>'rw',
                  isa=>'RegexpRef',
                  default=>sub{qr/img\s*.*src=\"(?<src>.*?)\"\s*.*/i});

has 'query'=>(is=>'rw',
                  isa=>'RegexpRef',
                  default=>sub{my $field=shift ; qr/img\s*.*$field=\"(?<field>.*?)\"\s*.*/i; });
# these two parameters are used to adjust to the device screen size  		  
has 'screen_w' =>(is => 'rw', isa => 'Int', required => 0,default =>1280) ;
has 'screen_h' =>(is => 'rw', isa => 'Int', required => 0,default =>800) ;

# regex looking for "=for html" blocks and tags <p> ou <span>  for the routine "show"
# work with the following kind of template
#<img style="width: 100px; height: 100px;" alt="logo" src="./img/coq_100x100.png">

#my $regtag=qr{^=for\s+html\s*
#			(?<tag><(span|p).*>\s*</(span|p)*>)}x;
has 'regtag'=>(is=>'rw',
                  isa=>'RegexpRef',
                  default=>sub{qr{^=for\s+html\s*
			(?<tag><(span|p).*>\s*</(span|p)>)}x;});
			  			 
has 'regimg' =>(is=>'rw',                 
			isa=>'RegexpRef',
			default=>sub{qr{<img  .* width\s*: \s* (?<wd>\d*)  .*      # value of width
                                                  height \s*: \s* (?<ht>\d*)                     # value of height
						    .*>}x ;});

# thes are the temporary intermediate files necessary to the jobs
has 'html'  => (
		is =>'rw',
                isa =>'Str',
                default =>sub {
		my $self=shift ;
		my $fh=File::Temp->new(TEMPLATE=>'garbageXXXX',
					   DIR => '.',
					   SUFFIX => '.html',
					   UNLINK => 1);
                    binmode( $fh, ":encoding(UTF-8)" );
                    my $fname = $fh->filename;
		    } );
		    
has 'target'=>(
		is =>'rw',
                isa =>'Str',
                default =>sub {
		my $self=shift ;
		my $fh=File::Temp->new(TEMPLATE=>'pod2odfXXXX',
					   DIR => '.',
					   SUFFIX => '.odt',
					   UNLINK => 1);
                    binmode( $fh, ":encoding(UTF-8)" );
                    my $fname = $fh->filename;
		    } );
		    
has 'pregmlf'=>(
		is =>'rw',
                isa =>'Str',
                default =>sub {
		my $self=shift ;
		my $fh=File::Temp->new(TEMPLATE=>'pregmlfXXXX',
					   DIR => '.',
					   SUFFIX => '.odt',
					   UNLINK => 1);
                    binmode( $fh, ":encoding(UTF-8)" );
                    my $fname = $fh->filename;
		    } );

# internal parameter
has 'param' =>(is =>'rw', 
			isa =>'HashRef[Str]',
			lazy=>1,
			default=>sub{my $self=shift ;
				{pod=>$self->pod ,
				target=>$self->target	
					}
				
				});

# routines and embedded in mouse triggers
has 'pod2pdf' =>(is=>'rw',
                  isa=>'Str',
		  trigger=>\&_pod2pdf,
		  );

has 'pod2odf' =>(is=>'rw',
                  isa=>'Str',
		  trigger=>\&_pod2odf,
		  );

sub _pod2odf {
	
# generation with images "normal"
	my $self=shift ;
	my $new=shift // $self->{gmlf};
	my $old=shift ;
	$self->{gmlf}=$new ;
	$self->{made_for}="normal" ;
	
	&post_pod2odf ($self) ;
return ;
}

has 'pod2gmlf' =>(is=>'rw',
                  isa=>'Str',
		  trigger=>\&_pod2gmlf,
		  );

sub _pod2gmlf {
	my $self=shift ;
	my $new=shift // $self->{gmlf}; 
	my $old=shift ;
	$self->{gmlf}=$new ;
	$self->{made_for}='gmlf' ;
	&post_pod2odf ($self) ;
return ;	
}

has 'show' =>(is=>'rw',
                  isa=>'Str',
		  trigger=>\&_show,
		  );

sub _show {
	my $self=shift ;
	$self->{showfile}=shift // $self->{showfile};
	my $old=shift ;
	&post_show($self) ;
	return ;
}

sub _pod2pdf {
# PDF generation if .odt exists
# if $new is not defined then default parameters is taken : gmlf.odt (see above)
# needs are path and program name of libreoffice or similar (e.g. openoffice)

	my $self=shift ;	
	my $new=shift // $self->pod2pdf ;
	my $old=shift ;

my $cwd = cwd() ;
# probleme with 'Program Files' ? so :
my $soffice_dir=&bugdir(@{$self->soffice_dir}) ;
chdir $soffice_dir or croak "can't change dir" ;
 
# for windows : only one  -  with convert-to obsolete for next version of LibeOffice
#"C:\Program Files\LibreOffice 4.0\program\soffice.exe" -headless -convert-to pdf --outdir ../mybdmongo1 first.odt
my $soffice=$self->soffice_exe ;

my $cmdload="$soffice --headless --convert-to pdf --outdir $cwd $new";

if( -e $new){
	system("$cmdload") == 0 or croak "system import failed: $?" ;
}   
else {
	say "file  $new doesn't exist "; }	

return ;

}

sub bugdir{
return join q{\\}, @_ ;
}

sub post_pod2odf {
	
my $self=shift ;

$0=__PACKAGE__ ;

# get the parameters

say "START of $0 - pod2odf" ;

my $made_for =$self->{made_for} ;

my $scaledown=$self->{scaledown} ;

lpod->set_input_charset($self->{pod_car}) ;
lpod->set_output_charset($self->{odf_car}) ;

my $from=lpod->get_input_charset() ; 
my $to=lpod->get_output_charset() ;

my $debug=1; #for some debugging must be set to 0

my %num ; # numbering titles
$num{head1}=0 ; # pour eviter undef si absence d'un title
$num{head2}=0 ;
$num{head3}=0 ;
$num{head4}=0 ;

our %callback ; # setting the trick
our $trickreg='(#\d+#)' ; #regex

# style et casse du modèle GMLF

our @gmlf_stylepara=qw/Titre chapeau code console iquestion ireponse legende Normal note pragma Signature/ ;

our @gmlf_stylechar=qw/code_em code_par exposant gras indice italic menu url ItaliqueGras/ ;

my @gmlf_styletitre=('Titre 1', 'Titre 2', 'Titre 3', 'Titre 4') ;

my $p_item ;
my $level ;
my @level_stack ; # nested level list
my $over_back=0 ; # flag for concatenation item with the next line 
my $lazy_txt ;
my $first_item=0 ;

my $podhtml = Pod::HtmlEasy->new(    
    on_H        => sub {
                    my ( $this , $text ) = @_ ;
		    my $txt=decode_entities($text);
                    # H as hat for style "chapeau"
                    my $p=odf_paragraph->create(text=>$txt,style=>"chapeau") ;
                    my $contexte = $PodODFtools::doc->get_body;
                    $contexte->append_element($p);
                    return  ;
    },
        on_A        => sub {
                    my ( $this , $text ) = @_ ;
		    my $txt=decode_entities($text);
                    # A as author for style "signature"
                    my $p=odf_paragraph->create(text=>$txt,style=>"Signature") ;
                    my $contexte = $PodODFtools::doc->get_body;
                    $contexte->append_element($p);
                    return  ;
    },
    
    on_Q        => sub {
                    my ( $this , $text ) = @_ ;
		    my $txt=decode_entities($text);
                    # T for Title, must preceded by =pod
                    #say "Titre = $txt" ;
                    my $style="Titre" ;
                    my $t=odf_heading->create(style=> $style,text => $txt, level => 1);
                    my $contexte = $PodODFtools::doc->get_body;
                    $contexte->append_element($t);
                    return  '';
                            
                    },
    
    on_head1     => sub {
			 my $this = shift ;
			  my ($text ,$a_name ) = @_ ;
		    my $txt=decode_entities($text);
                       $a_name=$txt ;
		       
                      my $style= $txt =~ /chapeau/i ? "chapeau" : "Titre 1" ;
                      $num{head1}++ unless ($style =~ /chapeau/) ;
                      $num{head2}=0 ;
                      $num{head3}=0 ;
                      $num{head4}=0 ;
                      my $title = "$num{head1}" . '. ' . $txt ;
                     
                      my $t=odf_heading->create(style=> $style,text => $title, level => 1);
                      my $contexte = $PodODFtools::doc->get_body;
                      $contexte->append_element($t);
                      
                      return "<a name='$a_name'></a><h1>$txt</h1>\n\n" ;
                    } ,
  
    on_head2     => sub {
			 my $this = shift ;
			   my ($text ,$a_name ) = @_ ;
		    my $txt=decode_entities($text);
                       $a_name=$txt ;
		       
                      $num{head2}++ ;
                      $num{head3}=0 ;
                      $num{head4}=0 ;
                      my $style="Titre 2" ;
                      my $title = "$num{head1}" . '.' . "$num{head2}" . ' ' . $txt ;
                      my $t=odf_heading->create(style=> "Titre 2",text => $title, level => 2);
                      my $contexte = $PodODFtools::doc->get_body;
                      $contexte->append_element($t);
                      return "<a name='$a_name'></a><h2>$txt</h2>\n\n" ;
                    } ,
  
    on_head3     => sub {
			 my $this = shift ;
			   my ($text ,$a_name ) = @_ ;
		    my $txt=decode_entities($text);
                       $a_name=$txt ;       
		       
                      $num{head3}++ ;
                      $num{head4}=0 ;
		      
                      my $title = "$num{head1}" . '.' . "$num{head2}" . '.' . "$num{head3}" . ' ' . $txt ;
                      my $t=odf_heading->create(style=> "Titre 3",text => $title, level => 3);
                      my $contexte = $PodODFtools::doc->get_body;
                      $contexte->append_element($t);
                      return "<a name='$a_name'></a><h3>$txt</h3>\n\n" ;
                    } ,
  on_head4     => sub {
			 my $this = shift ;

                       my ($text ,$a_name ) = @_ ;
		    my $txt=decode_entities($text);
                       $a_name=$txt ;                      
                      $num{head4}++ ;
     
                      my $title = "$num{head1}" . '.' . "$num{head2}" . '.' . "$num{head3}" . '.' . "$num{head4}" . ' ' . $txt ;
                      my $t=odf_heading->create(style=> "Titre 4",text => $title, level => 4);
                      my $contexte = $PodODFtools::doc->get_body;
                      $contexte->append_element($t);
                      return "<a name='$a_name'></a><h4>$txt</h4>\n\n" ;
                    } ,

  on_B         => sub {
                    my ( $this , $text ) = @_ ;
		    my $txt=decode_entities($text);
                    my $style ="gras" ;
		    &tour($txt,$style) ;
		    return $debug ? &tour($txt,$style) : "<b>$txt</b>" ;
                  } ,

  on_C         => sub {
                    my ( $this , $text ) = @_ ;
		    my $txt=decode_entities($text);
                    my $style ="code_par" ;
                    &tour($txt,$style) ;
                    return $debug ?  &tour($txt,$style) : "<font face='Courier New'>$txt</font>" ;
                  } ,
  
  on_E         => sub {
                    my ( $this , $text ) = @_ ;
		    my $txt=decode_entities($text);
		    my $NUL=q{\0} ;
		     $txt=~s{$NUL}{}gsmx;
		    say " **** passe par on_E !? ****  <$txt>" ;
 
		    return '<' if $txt =~ /^&lt;$/i ;
                    return '>' if $txt =~ /^&gt$/i ;
                    return '|' if $txt =~ /^verbar$/i ;
                    return '/' if $txt =~ /^sol$/i ;
		    return '&' if $txt =~ /^&amp;$/i ;
		     return '\'' if $txt =~ /^&quot;$/i ;
		    return chr($txt) if $txt =~ /^\d+$/ ;
                  },

  on_I         => sub {
                    my ( $this , $text ) = @_ ;
		    my $txt=decode_entities($text);
                    my $style = "italic";
                    &tour($txt,$style) ;
                    return $debug ?  &tour($txt,$style) :"<i>$txt</i>" ;
                  } ,

  on_L         => sub {
		    my $this=shift ;
		    my  ($page,$L0 , $text , $section, $type ) = @_ ;
		    my $L=decode_entities($L0);
                    my $style ="url" ;
                    &tour($L,$style) ;
                    return $debug ?  &tour($L,$style) :"<a href='$page' target='_blank'>$text</a>" ;
                  } ,
                  
  on_F         => sub {
                   my ( $this , $text ) = @_ ;
		    my $txt=decode_entities($text);
                    my $style ="ItaliqueGras" ;
                    &tour($txt,$style) ;
		    return $debug ?  &tour($txt,$style) : "<b><i>$txt</i></b>" ;
                  },

  on_S         => sub {
                    #set unbreable space;
                    my ( $this , $text ) = @_ ;
		    my $txt=decode_entities($text);
		    (my $txthtml=$txt)=~ s/\n/ /gs ;
		    my $car_unbr=($to =~/UTF-8|UTF8/i) ? "\xC2\xA0" : "\xA0" ;
    		    #~ $txt =~ s/\s/$car_unbr/g;
		    $txt =~ s/\s/\xA0/g;

                    my $style = "Normal" ;
                    &tour($txt,$style) ;
		    return $debug ?  &tour($txt,$style) : $txthtml ;
                  },

  on_Z         => sub { return '' ; },
  
  on_verbatim  => sub {
                    my ( $this , $text ) = @_ ;
		    my $txt=decode_entities($text);
		    my $txthtml=$txt ;
                    # 70 characters/column max pour GLMF)
                    use Text::Wrap qw(wrap $columns $huge);
                    my $indent=4 ;
                    my $pad = ' ' x $indent;
                    $pad='' ;
		    my $style="Normal";
		    # empty lines are skipped
		    if($txt !~/^\s*$/){  
                    local $Text::Wrap::unexpand = 0 ;
                    $Text::Wrap::columns = 70;
		    $Text::Wrap::huge = 'overflow';
                    $txt=wrap($pad, $pad, $txt) ."\n\n"  // ""; 
		    $style="code" ;}

                    my $p=odf_paragraph->create(text=>$txt,style=>$style) ;
                    my $contexte = $PodODFtools::doc->get_body;
                    $contexte->append_element($p);
                    return $debug ? $txt : ($txt !~ /\S/s ? '' : "<pre>$txt</pre>\n");
                  } ,

  on_textblock => sub {
                    my ( $this , $text ) = @_ ;
		    my $txt=decode_entities($text);
		    my $txt0=$txt ;	    
		    given($over_back){
			when (2){ # concat
			$over_back=1 ;
			$txt=$lazy_txt . $txt . ' ' ;
			}
			when (1){ # no concat
				 $txt=' ' x $level . $txt . ' ';
			 }
			 default {} ;
			 }
		    my $contexte = $PodODFtools::doc->get_body;
	            my $p=odf_paragraph->create(text=>$txt,style=>"Normal") ; 
                    $contexte->append_element($p) ;
		    
		    return "<p>$txt0</p>\n" ;
                  } ,

  on_over      => sub {
		    push @level_stack,$level ;
                    my ( $this)=shift ;
		    ($level ) = @_ ;
		    $level=4 if($level !~m/[0-9]+/);
		    # $first_item=1 ;
		    return "<ul>\n" ;
                  } ,

  on_item      => sub {
	  
	           my $this = shift ;
                   my ( $text , $a_name ) = @_ ;
                   my $txt=decode_entities($text);
		    $a_name=$txt ;
		    # whitespaces deleted for a correct left alignment
		    $txt =~ s/^\s//gs; 
		    $txt='*' if $txt eq '' ; # put a * if empty
                    my $txt0=' ' x $level . $txt . ' ' ;
		    $lazy_txt=$txt0 ;
		    
		    $over_back=1 ;
		    if ($txt=~/^(?:\s*\**\s*|\s*\d+\.\s*)$/ ){ 
		    $over_back++ # flag item for concatenation with next text
	            }
		   else { 
                   my $p=odf_paragraph->create(text=>$txt0,style=>"Normal") ; 
		   my $contexte = $PodODFtools::doc->get_body;
		   $contexte->append_element($p) ;
	           }
		   return"<li>" if $txt =~ /^(?:\*|\s*<[bi]\s*>\s*\*\s*<\/[bi]\s*>)$/si ;
		   return"<li><a name='$a_name'></a><b>$txt</b></li>\n" ;
                  } ,

  on_back      => sub {
                    my $this = shift ;
#		     pop @level_stack ; # pseudo balance
		    $level=pop @level_stack ; 
		    $over_back=0 if scalar @level_stack ==0 ;
		    return "</ul>\n" ;
                    } ,
                  
  on_for       => sub { 
        my($this, $txt) = @_;
	# ignore les =for comment
	my $text=decode_entities($txt);
	if ($text =~ m/^\s*comment/) {return ''; }
	
=head1 version 1

	$text=~/img\s*.*style=\"(?<style>.*)\"\.*/i ;
	my $style=$+{style} // "";
	$text=~/img\s*.*alt=\"(?<alt>.*)\"\s*.*/i ;
	my $alt=$+{alt} // "";
	$text=~/img\s*.*src=\"(?<src>.*?)\"\s*.*/i ;
	my $src=$+{src} // '.\NoSource.svg' ;
	
=head1 version 3

my ($style,$alt,$src)=("","",'./img/NoSource.svg') ;
for my $str ("style","alt","src"){
	$text=~/$self->query($str)/ ;
	 ${$str}=$+{field} // $$_ ;
}

=cut


=head1 version 2
=cut
	$text=~$self->{regex_for_html_style} ;
	my $style=$+{style} // "";
	
	$text=~/$self->{regex_for_html_alt}/ ;
	my $alt=$+{alt} // "";
	
	$text=~/$self->{regex_for_html_title}/ ;
	my $title=$+{title} // "";
	
	
	$text=~/$self->{regex_for_html_src}/  ;
	my $src=$+{src} // './img/NoSource.svg' ;	

        state $fig_num  ;
	
        $fig_num++ ;
	
	my $pragma1="/// Image: $src /// \n" ;
	my $legend=" Fig." . $fig_num ." : $alt \n" ;
	my $pragma2= "/// Fin Légende ///  \n" ;
	from_to( $pragma2,"utf8","cp1252") ;
	
	#say "légend : $legend $pragma2" ; 
	if($made_for eq 'gmlf') {
			 
         $PodODFtools::doc->get_body->append_element(odf_paragraph->create(
                                            text=>$pragma1,
                                            style=>"pragma") );
         $PodODFtools::doc->get_body->append_element(odf_paragraph->create(
                                            text=>$legend,
                                            style=>"legend") );
        $PodODFtools::doc->get_body->append_element(odf_paragraph->create(
                                            text=>$pragma2,
					style=>"pragma") );
	}
# if not gmlf
	else {
		$src=~ s/\//\\/g ;
		# modif 6/6/2014
		$legend="\n Fig." . $fig_num ." : $title \n" ;
		 my $p=$PodODFtools::doc->get_body->append_element(odf_paragraph->create(
                                            text=>$legend,
                                            style=>"legend") );
		my $regimg=qr{<img  .* width\s*: \s* (?<wd>\d*)(?<uw>\w{0,2})  .*        # value of width
                                                  height \s*: \s* (?<ht>\d*)(?<uh>\w{0,2})    # value of height
						    .*>}x ;
		$text=~/$regimg/ ;
		my ($image, $size) =  $PodODFtools::doc->add_image_file($src);
		# px is not a libreoffice unit must used pt instead
		$size->[0]=$+{wd}/$scaledown . 'pt' ;
		$size->[1]=$+{ht}/$scaledown .  'pt' ;
		
		my $link = $PodODFtools::doc->add_image_file($src);
		
		$p->insert_element(odf_create_image_frame(
										 $link,
										image          =>  $image,
										size            =>   $size,
										name           =>  $legend,									
									#        style           => "Classic",
									#        position        => "4cm, 8cm",
									#        page            => 1
								)
				);
	}	
	
        return ''; # for html
  },
     
  on_include   => sub {
                    my ( $this , $file ) = @_ ;
                    return "./$file" ;
                  },
  
  on_uri       => sub {
                    my ( $this , $uri ) = @_ ;
                    my $p=odf_paragraph->create(text=>$uri,style=>"console") ;
                    my $contexte = $PodODFtools::doc->get_body;
                    $contexte->append_element($p);
                    return '' ;
                  },
  
  on_error     => sub {
                    my ( $this , $txt ) = @_ ;
                    return "<!-- POD_ERROR: $txt -->" ;
                  } ,

  on_index_node_start => sub {
                           my ( $this , $txt , $a_name , $has_childs ) = @_ ;
                           my $ret = "<li><a href='#$a_name'>$txt</a>\n" ;
                           $ret .= "\n<ul>\n" if $has_childs ;
                           return $ret ;
                         } ,

  on_index_node_end => sub {
                         my $this = shift ;
                         my ( $txt , $a_name , $has_childs ) = @_ ;
                         my $ret = $has_childs ? "</ul>" : '' ;
                         return $ret ;
                       } ,

 ) ;
  
 # import style  from the model $model
my $model=$self->{model} ;
our $doc = odf_document->get($model);

my $contexte = $doc->get_body;
$contexte->clear() ;

# insert a proprietary style : "ItaliqueGras"
$doc->insert_style(
    odf_style->create(
    'text',
    name => "ItaliqueGras",
    style => 'italic',
    weight => 'bold',
    background_color => 'yellow'
    )
    ) ;
   
# proprietary style if any need for image    
#~ $PodODFtools::doc->insert_style( odf_create_style('paragraph',name    => "Centered",align   => 'center'));
#~ $PodODFtools::doc->get_body->append_element(odf_create_paragraph(style => "Centered")

# start parsing
# version htmleasy 1.19
$podhtml->pod2html($self->{pod},"output",$self->{html} ) ;

# save a first pass file
$doc->save(target => $self->{target} );

&lpod_replace() ;

my $prefile=$self->{pregmlf} ;

$doc->save(target =>$prefile );

# NUL='\0' is an illegal character in XML so it must be filtered
# Read the odf file and clean, write back

my $zip = Archive::Zip->new();
   unless ( $zip->read( $prefile ) == AZ_OK ) {
       croak  'read error'; }

my $newtxt=$zip->contents('content.xml');
my $NULL=qq{\0} ;
$newtxt=~s/$NULL//gm ;

$zip->contents( 'content.xml',$newtxt);
my $zipfile=$self->{gmlf}  ;
my $status = $zip->writeToFileNamed(  $zipfile );
croak "error somewhere : $status" if $status != AZ_OK;

 
say "END of $0 - pod2odf" ;

sub tour {
# replace by #random number# and convert to UTF8
    my ($text,$style)=@_ ;
    my $trick='#' .int( rand(10000)).'#' ;
# put the text and style in %callback
    $callback{$trick}={style=>$style,content=>$text} ;
#   say "trick : $trick $style $text " ;
    return "$trick" ;
}
          

sub lpod_replace {
# set sthe style and replace the stubs with their values
# first step is for the paragraph style group (@gmlf_stylepara)
# style paragraphes

    	my $context = $PodODFtools::doc->get_body;
	my $fulltext=$context->get_text(recursive => TRUE)  ;

	#~ my $carcod='#!!!5' ;
	#~ $fulltext=~s/$carcod/&/g ;

        while($fulltext =~ /$trickreg/g ){
         
            my $search=$1 ;
            my $replace=$callback{$search}{content} ;
            my $stylename=$callback{$search}{style} ;

            if($stylename~~ @gmlf_stylepara){
                my $paragraph = $context->get_paragraph(content => $search) ||
                croak "content = <$search>  - <$replace> - $stylename";
                my $text = $paragraph->get_text(recursive => TRUE) ;
                $text =~ s/$search/$replace/ ;
                $paragraph->set_text($text);
                $paragraph->set_style($stylename)
                }
        }
        
# second step for the character style group
#(no check on @gmlf_stylechar because there are only two kind of styles)
# replacement must be done before setting the style
# because this will reset to a default style.

# the following is a work around solution based on position
# because get_paragraph(content =>"$link",style=>$style) crash

# for that reason we have to deal for crlf character and
#the length of utf8 character

my @offset ;
my @lg ;
my @style ;
my @lg1 ;

    	$context = $PodODFtools::doc->get_body ;
        for my $p ($context->get_paragraphs(recursive => TRUE)){
            my $text=$p->get_text(recursive => TRUE) ;
	    
            my $m=0 ;
	    # delete double space and/or substitute crlf with space
            $text=~ s/\s+ |\n/ /mg; 

            my $tt=$text ;

            while ($text =~ /$trickreg/g ){
                my $dollar=$1 ;               
                if (defined($callback{$dollar}{content})){
                    $style[$m]=$callback{$dollar}{style} ;
                    $lg[$m]=length($callback{$dollar}{content}) ;
                    my $replace=$callback{$dollar}{content} ;
		    (my $r=$replace)=~s/\n/ /gm ;
		    $lg[$m]=length($r) ;
                    my @cut=split /$dollar/, $text ;
                    $cut[0].='' ; 
                    my $cutn=$cut[0] ;
                    $cut[1] .='' ;
                    # delete crlf's not counted in lpod
                    $cutn =~s/\n//gm ;
                    $offset[$m]=length($cutn) ;
                    $text=$cut[0] . $replace . $cut[1] ;
		    # delete double space not seen  with tagged texts
		    $text=~ s/\s+ / /mg; 
                    $m++ ;                   
                }
            }
            if(@lg) {
                $p->set_text($text);
                $p->set_span(
                         offset=>"$offset[$_]",
                         length=>"$lg[$_]",
                         style=>"$style[$_]") for (0..$#lg) ;
            }
            @lg=() ;
            @offset=() ;
            @style=() ;
        }

}

}

sub post_show{

=head1 synopsis

show

make the html files from the .pod file as show_page_n, numbered from 0 to N, linked together by a precede and a next link, access done by click on the left
side area and right one

=cut

=head1 format  =for html

=for html <p class="illustration"><img  style="width: 640px; height: 400px;" src="./img/HT-XML.jpg" 
alt="[La famille HT-XML]" title="La famille HT-XML" /></p>

=cut

=head1 html script used for linking

<img src="planets.gif" width="145" height="126" alt="Planets"
usemap="#nagivmap">
# separation de la page en deux
<map name="navigmap">
<area shape="rect" coords="0,0,$widthmiddle,$height" href="$predpage" alt="predpage">
<area shape="rect" coords="0,$widthmiddle,$widthmax,$height" href="$nexpage" alt="nextpage">

head1 pod format  =for html

=for html <p class="illustration"><img  style="width: 640px; height: 400px;" src="./img/HT-XML.jpg" 
alt="[La famille HT-XML]" title="La famille HT-XML" /></p>

=cut

=head1  screen size

# paramètres écran VGN-SZ2HP/B
my $z_ecran_w=1280 ;
my $z_ecran_h=800 ;

# paramètres écran Sony Xperia SP
$z_ecran_w=720 ;
$z_ecran_h=1280 ;

=pod xperia

my $z_ecran_w=1280 ;
my $z_ecran_h=720 ;

=cut

# paramètres
my $self=shift ;

$0=__PACKAGE__ ;

# get the parameters

say "START of $0 - show" ;

# fichier source
my $pod=$self->{pod} ;
# fichier de sortie
my $filename=$self->{showfile} ; # path . filename . number . html

my $z_ecran_w=$self->{screen_w} ;
my $z_ecran_h=$self->{screen_h} ;

#  regex qui récupère les paramètres des images - depend de l'ordre
my $regimg=$self->{regimg} ;
my $regtag=$self->{regtag} ;

# paramètres d'ajustement d'échelle
my $k_zoom=0.8 ; # le zoom est trop important réduction par ce facteur correctif
open(my $fhin, "<", $pod) or croak "cannot open file $pod ";

my $htmlheader=<< "HEADER" ;
<?xml version="1.0" ?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title></title>
<meta http-equiv="content-type" content="text/html; charset=utf-8" />
<link rev="made" href="mailto:" />
</head>

<body style="background-color: white">

HEADER

my $htmlend=<< "END" ;
</body>
</html>
END

my @lines=<$fhin> ;
#say $lines[0] ;

my @sublines ;
my $j=0 ;

# scan le fichier et récupère une ou plusieurs images du blocs
for my $i (0..$#lines){
if ($lines[$i] =~/$regtag/g) {
$sublines[$j] =$+{tag} ; $j++}
}

for my $i (0..$#sublines){
	
#	my $name=$filename. "_" . $i . ".html " ;
	my $show=$filename . "_" .  $i  . ".html " ;	
	open(my $fhout, "+>", $show) or croak "cannot open file $show ";
	say $fhout $htmlheader;
	my($w0,$h0)=($sublines[$i]=~/$regimg/g );
	# calcul d'un zoom fonction de l'écran
	my $zwe=$z_ecran_w/$w0 ;
	my $zhe=$z_ecran_h/$h0 ;
	my $zoom=1 ; 
	if ($zhe >=1 && $zwe >=1){ $zoom= $zhe > $zwe ? $zwe : $zhe  ;}
	if( $zhe < 1.0 && $zwe < 1.0) {
		$zoom= $zhe > $zwe ? $zhe : $zwe  ;}
	my$w =$zoom* $w0 *$k_zoom ;
	my $h =$zoom*$h0 *$k_zoom ;
#	say "$i $tag --- $w $h ";
	$sublines[$i]=~s!(<img .*)/>!$1 usemap="#navigmap" />!g ;
	$sublines[$i]=~s!$w0!$w!g ;
	$sublines[$i]=~s!$h0!$h!g ;
	say $fhout $sublines[$i] ;
	say $fhout "<map name=\"navigmap\">" ;
	my $widthmiddle=$k_zoom*$zoom*$w0/2 . 'px';
	$w .= 'px'  ;
	$h .= 'px'  ;
	my $ip = $i-1 >= 0 ? $i-1 : 0 ;
	my $predpage="$filename" ."_" . $ip . ".html " ;
	say $fhout "<area shape=\"rect\" coords=\"0,0,$widthmiddle,$h\" href=\"$predpage\" alt=\"predpage\">" ;
	my $in = $i+1 <= $#sublines ? $i+1 : $#sublines ;
	my $nexpage="$filename" ."_". $in . ".html " ;
	say $fhout "<area shape=\"rect\" coords=\"$widthmiddle,0,$w,$h\" href=\"$nexpage\" alt=\"nextpage\">" ;
	say $fhout $htmlend ;
	close $fhout or croak "cannot close $fhout" ;
}

say "END of $0 - show" ;
return  ;

}

=head1 pod2odf.pl

This script is strongly intended to be used for technical papers
for GMLF (GNU Linux Magazine France,  L<http://www.ed-diamond.com/articles/guide_auteur.pdf>) .
Generally, French Mongers used the pod for writing their papers,
but the editor needs to receive them under different formattings,
one of them is ODF.
But thie version 1.3 is an update, where images could be inserted into the text, if the new make-for parameter is not set to 'gmlf' considered as a special purpose.

B<Note :>
This script is delivered with windows-1252 character set.
Of course it could be changed into utf8, but this has not
been tested in this case and so the behavior of this program
could be modified.

B<Warning :>
As white-space sequence with more than one character are considered as illegal, they are reduced to one.

package Pod::HtmlEasy::Parser; Readonly::Scalar my $NUL => NUL; statement
must be replaced by "my $NUL =q{};" because it make LibreOffice not opening finding illegal characters:
"Erreur de lecture.
Erreur de format dans le fichier du sous-document content.xml à la position 2,5739(row,col)."

=head1 VERSION

Version 1.31

=head1 SYNOPSIS

Translation from Pod to ODF document.

The command linesS< :>

pod2odf.pl --model $model --pod $pod_file --gmlf $file_gmlf --html $html_file --pod_car 'cp1252' --odf_car 'cp1252' --target firstpass.odt --made_for gmlf  | normal

with the following parameters (only the two first are always required)S< :>

$model      :"your model (diamond_editions.ott) " 
$pod_file   :" the pod file as the source document" ;
$file_gmlf  : "your paper translated in ODF" ;
html_file   : garbage html file (just to change nothing in Pod::HtmlEasy)" ;
$target     :   " intermediate file in ODF" ;
pod_car     : the character police used for the pod
odf_car     : the police used for outputting the odf document
made_for  : allow to choose how the images are interpreted for the ODF document

=head1 DOC Supplement

This script is based on the two following packages :

=over

=item ODF::lpOD;
    
=item Pod::HtmlEasy ;

=back

The documentation of the last above package described how to adapt it on others types of translation. That's just what we have done for ODF.

We have added three "new" tags for making things simpler instead using the tag "=meta". The first one <H "for Header"> is for setting the so-called in french "chapeau", a brief introduction to the technical paper.
The second one <A "the great author name"> for being able to use the style of "signature" to set the author name for the document.
The last one <Q "The Main title"> is dedicated to use the style "Title".

(Important feature you must put at the begginning of the document "=pod" or equivalent to swith to the pod mode if you use the above tags at first).

The images/figures are included by the following kind of statement :

    =for html
    '<img style="the style width,height " alt="the name of the figure" src="path/file.ext(.jpg,.png etc.)">' ;
    
    example :
    
    <img style="width: 100px; height: 100px;" alt="logo" src="GpxLeFilm/coq_100x100.png"><br>
    
The title and figure numbering are automatically set by the program.
The "=item" are also made under the editor requirements (but could be easily changed to their original structure ; see Pod::HtmlEasy again).

The  "=for comment" are skipped of the target document.

(B<Note :>
Due to the structure used, even if an HTML file is generated, it must be considered as a corrupted file in the sense as lot of datas are missing.)

=cut

=head1 AUTHOR

Ch.Minc, C<< <=charles.minc at wanadoo.fr> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-proto_ipod at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=pod2odf.pl>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc proto_ipod


You can also look for information at:

Where you coulf find the document guide for writing articles :

L<http://www.ed-diamond.com/articles/guide_auteur.pdf>

Where this program could be downloaded :

L<git://gist.github.com/1143721.git>


=head1 ACKNOWLEDGEMENTS

Thanks to Jean-Marie Gouarné for his help and useful remarks.

=head1 LICENSE AND COPYRIGHT

Copyright 2011 Ch.Minc.(French Monger Ass.)

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.

=head1 Known bugs

1/ Does'nt support tags in the title

	example :
		=head1  S<This >title does'nt work
		
2/ =item

The behavior of the above tag could be slightly different as defined in S<L<http://perldoc.perl.org/perlpod.html#Hints-for-Writing-Pod> :>
 And perhaps most importantly, keep the items consistent: either use "=item *" for all of them,
to produce bullets; or use "=item 1.", "=item 2.", etc., to produce numbered lists; or use "=item foo", "=item bar", etc.
--namely, things that look nothing like bullets or numbers.
	
	
=cut

# End of pod2odf.pl



#===============================================================================
# Standard Moose cleanup.
#===============================================================================

no Moose;
__PACKAGE__->meta->make_immutable;

__END__
    