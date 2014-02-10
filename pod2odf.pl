#!c:/Perl/bin/perl.exe
####-----------------------------------
### File	: pod2odf.pl
### Author	: Ch.Minc
### Purpose	: pod to odf from htmleasy
### Version	: 1.1 15/08/2011 
### Version	: 1.2 15/02/2012 
### Version	: 1.3 12/07/2012 
### Version	: 1.31 21/01/2014
### copyright GNU license
####-----------------------------------


our $VERSION = '1.31';
use  5.12.3;
use strict ;
use warnings ;
use Carp ;
$Carp::Verbose='true' ;
use Data::Dumper;

use Encode ;
use charnames ':full' ;
#my $enc='utf-8' ;
my $enc='utf8' ;
use HTML::Entities;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

use ODF::lpOD 1.118 ;
use Pod::HtmlEasy 1.001009 ;

use Encode qw(from_to) ;

use Moose;
with 'MooseX::Getopt';

# get the parameters

#pod2odf.pl --model $model --pod $pod_file --gmlf $file_gmlf --html $html_file --pod_car 'cp1252' --odf_car 'cp1252'
# --target firstpass.odt --made_for normal|gmlf

has 'model' => (is => 'rw', isa => 'Str', required => 1);
has 'gmlf'  => (is => 'rw', isa => 'Str', required => 0,
                default=>'./gmlf.odt');
has 'html'  => (is => 'rw', isa => 'Str', required => 0,default =>'./garbage.html');
has 'pod'   => (is => 'rw', isa => 'Str', required => 1);
has target  =>  (is => 'rw', isa => 'Str', required => 0,default =>'./firstpod2odf.odt');
has pod_car  =>  (is => 'rw', isa => 'Str', required => 0,default =>'cp1252');
has odf_car  =>  (is => 'rw', isa => 'Str', required => 0,default =>'cp1252');
has made_for =>(is => 'rw', isa => 'Str', required => 0,default =>'gmlf') ;

say "START of $0" ;
#say $Text::Wrap::SUBVERSION ;

my $param =main->new_with_options();

my $made_for =$param->{made_for} ;

my $scaledown=4 ;

lpod->set_input_charset($param->{pod_car}) ;
lpod->set_output_charset($param->{odf_car}) ;

# from_to for encoding
#my $from='cp1252' ;
#my $to='utf-8' ;
my $from=lpod->get_input_charset() ; 
my $to=lpod->get_output_charset() ;

# note : strings for tag "=for" :
#          code translation done from cp1252 to $to by from_to()

say "pod character set to : ",lpod->get_input_charset() ;
say "odf character set to : ",lpod->get_output_charset() ;

my $debug=1; #for some debugging must be set to 0

my %num ; # numbering titles
$num{head1}=0 ; # pour eviter undef si absence d'un title
$num{head2}=0 ;
$num{head3}=0 ;
$num{head4}=0 ;

my %callback ; # setting the trick
my $trickreg='(#\d+#)' ; #regex

# style et casse du modèle GMLF

my @gmlf_stylepara=qw/Titre chapeau code console iquestion ireponse legende Normal note pragma Signature/ ;

my @gmlf_stylechar=qw/code_em code_par exposant gras indice italic menu url ItaliqueGras/ ;

my @gmlf_styletitre=('Titre 1', 'Titre 2', 'Titre 3', 'Titre 4') ;

my $p_item ;
my $level ;
my @level_stack ; # nested level list
my $over_back=0 ; # flag for concatenation item with the next line 
my $lazy_txt ;
my $first_item=0 ;

my $podhtml = Pod::HtmlEasy->new(    
    on_H        => sub {
                    my ( $this , $txt ) = @_ ;
                    # H as hat for style "chapeau"
                    # from_to($txt, $from,$to) ;
                    my $p=odf_paragraph->create(text=>$txt,style=>"chapeau") ;
                    my $contexte = $main::doc->get_body;
                    $contexte->append_element($p);
                    return  ;
    },
        on_A        => sub {
                    my ( $this , $txt ) = @_ ;
                    # A as author for style "signature"
                    # from_to($txt, $from,$to) ;
                    my $p=odf_paragraph->create(text=>$txt,style=>"Signature") ;
                    my $contexte = $main::doc->get_body;
                    $contexte->append_element($p);
                    return  ;
    },
    
    on_Q        => sub {
                    my ( $this , $txt ) = @_ ;
                    # T for Title, must preceded by =pod
                    say "Titre = $txt" ;
                    # from_to($txt, $from,$to) ;
                    my $style="Titre" ;
                    my $t=odf_heading->create(style=> $style,text => $txt, level => 1);
                    my $contexte = $main::doc->get_body;
                    $contexte->append_element($t);
                    return  ;
                            
                    },
    
    on_head1     => sub {
 #                     my ( $this , $txt , $a_name ) = @_ ;
#                      print "verifie head1: $txt $a_name $0 \n" ;
# modif 2012/07/12 version 1.019 pod:HTMLEasy
			 my $this = shift ;
#			 say Dumper @_ ;
			  my ($txt ,$a_name ) = @_ ;
                       $a_name=$txt ;
                      my $style= $txt =~ /chapeau/i ? "chapeau" : "Titre 1" ;
                      # from_to($txt, $from,$to) ;
                      $num{head1}++ unless ($style =~ /chapeau/) ;
                      $num{head2}=0 ;
                      $num{head3}=0 ;
                      $num{head4}=0 ;
                      my $title = "$num{head1}" . '. ' . $txt ;
                     
                      my $t=odf_heading->create(style=> $style,text => $title, level => 1);
                      my $contexte = $main::doc->get_body;
                      $contexte->append_element($t);
                      
                      return "<a name='$a_name'></a><h1>$txt</h1>\n\n" ;
                    } ,
  
    on_head2     => sub {
 #                     my ( $this , $txt , $a_name ) = @_ ;
  #                    print "verifie head2: $txt $a_name \n";
                      # from_to($txt, $from,$to) ;
		      # modif 2012/07/12 version 1.019 pod:HTMLEasy
			 my $this = shift ;
#			 say Dumper @_ ;
			  my ($txt ,$a_name ) = @_ ;
                       $a_name=$txt ;
                      $num{head2}++ ;
                      $num{head3}=0 ;
                      $num{head4}=0 ;
                      my $style="Titre 2" ;
                      my $title = "$num{head1}" . '.' . "$num{head2}" . ' ' . $txt ;
                      my $t=odf_heading->create(style=> "Titre 2",text => $title, level => 2);
                      my $contexte = $main::doc->get_body;
                      $contexte->append_element($t);
                      return "<a name='$a_name'></a><h2>$txt</h2>\n\n" ;
                    } ,
  
    on_head3     => sub {
 #                     my ( $this , $txt , $a_name ) = @_ ;
  #                    print "verifie : $txt $a_name \n";
                      # from_to($txt, $from,$to) ;
 # modif 2012/07/12 version 1.019 pod:HTMLEasy
			 my $this = shift ;
#			 say Dumper @_ ;
 my ($txt ,$a_name ) = @_ ;
                       $a_name=$txt ;                     
                      $num{head3}++ ;
                      $num{head4}=0 ;
                      my $title = "$num{head1}" . '.' . "$num{head2}" . '.' . "$num{head3}" . ' ' . $txt ;
                      my $t=odf_heading->create(style=> "Titre 3",text => $title, level => 3);
                      my $contexte = $main::doc->get_body;
                      $contexte->append_element($t);
                      return "<a name='$a_name'></a><h3>$txt</h3>\n\n" ;
                    } ,
  on_head4     => sub {
 #                     my ( $this , $txt , $a_name ) = @_ ;
######    modifdu 15/2/2012 undefined $a_name ?
#		      $a_name=$a_name // $txt ;
 #                     print "verifie : $txt $a_name \n";
                      # from_to($txt, $from,$to) ;
# modif 2012/07/12 version 1.019 pod:HTMLEasy
			 my $this = shift ;
#			 say Dumper @_ ;
                      my ($txt ,$a_name ) = @_ ;
                       $a_name=$txt ;                      
                      $num{head4}++ ;
     
                      my $title = "$num{head1}" . '.' . "$num{head2}" . '.' . "$num{head3}" . '.' . "$num{head4}" . ' ' . $txt ;
                      my $t=odf_heading->create(style=> "Titre 4",text => $title, level => 4);
                      my $contexte = $main::doc->get_body;
                      $contexte->append_element($t);
                      return "<a name='$a_name'></a><h4>$txt</h4>\n\n" ;
                    } ,

  on_B         => sub {
                    my ( $this , $txt ) = @_ ;
                    my $style ="gras" ;
		    &tour($txt,$style) ;
		    return $debug ? &tour($txt,$style) : "<b>$txt</b>" ;
                  } ,

  on_C         => sub {
                    my ( $this , $txt ) = @_ ;
                    my $style ="code_par" ;
                    &tour($txt,$style) ;
                    return $debug ?  &tour($txt,$style) : "<font face='Courier New'>$txt</font>" ;
                  } ,
  
  on_E         => sub {
                    my ( $this , $txt ) = @_ ;
		    my $NUL=q{\0} ;
		    # modif 2012/07/12 version 1.019 pod:HTMLEasy
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
                    my ( $this , $txt ) = @_ ;
                    my $style = "italic";
                    &tour($txt,$style) ;
                    return $debug ?  &tour($txt,$style) :"<i>$txt</i>" ;
                  } ,

  on_L         => sub {
 #                  my ( $this , $L , $text, $page , $section, $type ) = @_ ;
		# modif 2012/07/12 version 1.019 pod:HTMLEasy
#		    say Dumper @_;
		    my $this=shift ;
		    my  ($page,$L , $text , $section, $type ) = @_ ;
                    my $style ="url" ;
                    &tour($L,$style) ;
                    return $debug ?  &tour($L,$style) :"<a href='$page' target='_blank'>$text</a>" ;
                  } ,
                  
  on_F         => sub {
                    my ( $this , $txt ) = @_ ;
                    my $style ="ItaliqueGras" ;
                    &tour($txt,$style) ;
		    return $debug ?  &tour($txt,$style) : "<b><i>$txt</i></b>" ;
                  },

  on_S         => sub {
                    #set unbreable space;
                    my ( $this , $txt ) = @_ ;
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
                    my ( $this , $txt ) = @_ ;
		    
		    my $txthtml=$txt ;
                    # 70 characters/column max pour GLMF)
                    use Text::Wrap qw(wrap $columns $huge);
                    my $indent=4 ;
                    my $pad = ' ' x $indent;
                    $pad='' ;
		    my $style="Normal";
		    if($txt !~/^\s*$/){  # ne traite pas en code les lignes vides
                    local $Text::Wrap::unexpand = 0 ;
                    $Text::Wrap::columns = 70;
		    $Text::Wrap::huge = 'overflow';
                    $txt=wrap($pad, $pad, $txt) ."\n\n"  // ""; 
		    $style="code" ;}

                    my $p=odf_paragraph->create(text=>$txt,style=>$style) ;
                    my $contexte = $main::doc->get_body;
                    $contexte->append_element($p);
                    return $debug ? $txt : ($txt !~ /\S/s ? '' : "<pre>$txt</pre>\n");
  #  return "<pre>$txt</pre>\n" in HTML;
                  } ,

  on_textblock => sub {
                    my ( $this , $txt ) = @_ ;
		    ## mise au point 15/!02/2012
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
		    my $contexte = $main::doc->get_body;
	            my $p=odf_paragraph->create(text=>$txt,style=>"Normal") ; 
                    $contexte->append_element($p) ;
		    
		    return "<p>$txt0</p>\n" ;
                  } ,

  on_over      => sub {
		    push @level_stack,$level ;
                    my ( $this)=shift ;
		    ($level ) = @_ ;
		    $level=4 if($level !~m/[0-9]+/);
		    #~ $first_item=1 ;
		    return "<ul>\n" ;
                  } ,

  on_item      => sub {
	  
	           my $this = shift ;
# modif 2012/07/12 version 1.019 pod:HTMLEasy
                   my ( $txt , $a_name ) = @_ ;
 # modif 2012/07/12 version 1.019 pod:HTMLEasy
#			 say Dumper @_ ;
		    $a_name=$txt ;
		    # supprime les blancs à gauche pour marger correctement
		    $txt =~ s/^\s//gs; 
		    $txt='*' if $txt eq '' ; # put a * if empty
                    my $txt0=' ' x $level . $txt . ' ' ;
		    $lazy_txt=$txt0 ;
		    
                    # from_to($txt, $from,$to) ;
		    $over_back=1 ;
		    if ($txt=~/^(?:\s*\**\s*|\s*\d+\.\s*)$/ ){ 
		    $over_back++ # flag item for concatenation with next text
	            }
		   else { 
                   my $p=odf_paragraph->create(text=>$txt0,style=>"Normal") ; 
		   my $contexte = $main::doc->get_body;
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
	say "on_for : $text" ;
        # image pour GMLF
        # cf Html.pm ligne 1277
        # look for '<img style="'. $1 . '" alt="'. $2 . '" src="' . $3 .' ">' ;
        # interpretation normale
        # not any checking done like : return unless $text =~ /html / ;
	# cette regex dépend de l'ordre des parametres
        #$text=~/img\s*style=\"(.*)\"\s*alt=\"(.*)\"\s*src=\"(.*)\"\s*/i ;
	
	$text=~/img\s*.*style=\"(?<style>.*)\"\.*/i ;
	my $style=$+{style} // "";
	$text=~/img\s*.*alt=\"(?<alt>.*)\"\s*.*/i ;
	my $alt=$+{alt} // "";
	$text=~/img\s*.*src=\"(?<src>.*?)\"\s*.*/i ;
	my $src=$+{src} // '.\NoSource.svg' ;
        state $fig_num  ;
	
        $fig_num++ ;
	########### modif 15/02/2012
	
	my $pragma1="/// Image: $src /// \n" ;
	my $legend=" Fig." . $fig_num ." : $alt \n" ;
	my $pragma2="/// Fin Légende ///  \n" ;
	
	if($made_for eq 'gmlf') {
		
         #~ from_to($pragma1,"cp1252",$to);
         #~ from_to($pragma2,"cp1252",$to);
         #~ from_to($legend,"cp1252",$to);
	 
         $main::doc->get_body->append_element(odf_paragraph->create(
                                            text=>$pragma1,
                                            style=>"pragma") );
         $main::doc->get_body->append_element(odf_paragraph->create(
                                            text=>$legend,
                                            style=>"legend") );
        $main::doc->get_body->append_element(odf_paragraph->create(
                                            text=>$pragma2,
					style=>"pragma") );
	}
# if not gmlf
	else {
		$src=~ s/\//\\/g ;
		say "debug : $src , $fig_num " ;
		 my $p=$main::doc->get_body->append_element(odf_paragraph->create(
                                            text=>$legend,
                                            style=>"legend") );
		my $regimg=qr{<img  .* width\s*: \s* (?<wd>\d*)(?<uw>\w{0,2})  .*        # value of width
                                                  height \s*: \s* (?<ht>\d*)(?<uh>\w{0,2})    # value of height
						    .*>}x ;
		$text=~/$regimg/ ;
		my ($image, $size) =  $main::doc->add_image_file($src);
		# sol 1- calcul sur image
		#map{$size->[$_]=~s!(\d*)(\D*)!($1/$scaledown // '70').$2// 'pt'!ex;} 0..1 ;
		
		#sol2 d'aprés les infos dans le pod
		#$size->[0]=$+{wd}/$scaledown . $+{uw} ;
		#$size->[1]=$+{ht}/$scaledown . $+{uh} ;
		# note px semble mal compris de libreoffice
		
		$size->[0]=$+{wd}/$scaledown . 'pt' ;
		$size->[1]=$+{ht}/$scaledown .  'pt' ;
		say Dumper $size ;
		my $link = $main::doc->add_image_file($src);
		
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
                    # return "<a href='$uri' target='_blank'>$uri</a>" in html;
                    my ( $this , $uri ) = @_ ;
                    # from_to($uri, $from,$to);
                    my $p=odf_paragraph->create(text=>$uri,style=>"console") ;
                    my $contexte = $main::doc->get_body;
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
our $doc = odf_document->get($param->{model});
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
#~ $main::doc->insert_style( odf_create_style('paragraph',name    => "Centered",align   => 'center'));
#~ $main::doc->get_body->append_element(odf_create_paragraph(style => "Centered")

# start parsing
#$podhtml->pod2html($param->{pod},$param->{html} ) ;

# version htmleasy 1.19
$podhtml->pod2html($param->{pod},"output",$param->{html} ) ;

# save a first pass file
$doc->save(target => $param->{target} );

&lpod_replace() ;

$doc->save(target =>$param->{gmlf} );

# NUL='\0' is an illegal character in XML so it must be filtered
# Read the odf file and clean, write back
  
my $zip = Archive::Zip->new();
   unless ( $zip->read( $param->{gmlf} ) == AZ_OK ) {
       croak  'read error'; }

my $newtxt=$zip->contents('content.xml');
my $NULL=qq{\0} ;
$newtxt=~s/$NULL//gm ;

$zip->contents( 'content.xml',$newtxt);
my $zipfile='D:\perl\Lyon24Jan2014\xx.odf' ;
my $status = $zip->writeToFileNamed(  $zipfile );
croak "error somewhere : $status" if $status != AZ_OK;
  
say "END of $0" ;

sub tour {
# replace by #random number# and convert to UTF8
    my ($text,$style)=@_ ;
    my $trick='#' .int( rand(10000)).'#' ;
###################### modif 15/2/2012
##     from_to($text, $from,$to);
# put the text and style in %callback
    $callback{$trick}={style=>$style,content=>$text} ;
#   say "trick : $trick $style $text " ;
    return "$trick" ;
}
          

sub lpod_replace {
    
# set sthe style and replace the stubs with their values

# first step is for the paragraph style group (@gmlf_stylepara)
# style paragraphes

    	my $context = $doc->get_body;
	my $fulltext=$context->get_text(recursive => TRUE)  ;

	#~ my $carcod='#!!!5' ;
	#~ $fulltext=~s/$carcod/&/g ;
	
########### modif 15/2/2012 ?
###     $fulltext=decode_utf8($fulltext);
   
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

    	$context = $doc->get_body ;
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
