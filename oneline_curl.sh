#!/bin/bash


# ----- usage ------ #
usage()
{
 	echo "Version 0.03 [2018-06-01] "
	echo "USAGE: ./oneline_curl.sh <-i input_fasta> <-t server_type> <-o out_root> "
	echo "           [-d domain] [-n job_name] [-a curl_addi] [-k kill_temp] "
	echo "           [-l pend_time] [-L run_time] [-U url] "
	echo "***** required arguments ***** "
	echo "-i input_fasta :  input protein sequence file in FASTA format"
	echo "-t server_type :  'property' or 'contact' ,"
	echo "                  'property' for running RaptorX-Property jobs,"
	echo "                  'contact' for running RaptorX-Contact jobs."
	echo "-o out_root    :  output root. required parameter "
	echo "***** optional arguments *****"
	echo "-d domain      :  server domain. default is 'http://raptorx.uchicago.edu' "
	echo "-n job_name    :  job name. If not specified, "
	echo "                  then the prefix of 'input_fasta' would be used"
	echo "-a curl_addi   :  additional curl command. default is '' (null) "
	echo "                  e.g., ' --form No3DModels=true ' for contact jobs"
	echo "                  e.g., ' --form useProfile=false ' for property jobs"
	echo "-k kill_tmp    :  kill temporary folder. default is 1 (kill) "
	echo "-l pend_time   :  pending time limit. default is 480 min "
	echo "-L run_time    :  running time limit. default is 480 min "
	echo "-U url         :  processed URL for download (default null) "
	exit 1
}

if [ $# -lt 1 ];
then
	usage
fi
curdir="$(pwd)"

# ----- get arguments ----- #
#-> required
input_fasta=""
server_type=""
out_root=""
#-> optional
domain_name="http://raptorx.uchicago.edu"
job_name="null"
curl_addi=""
kill_tmp=1
#-> time limit
pend_time=1440
run_time=4320
#-> url
url=""

# ----- curl addi ------#
#curl_addi=" --form No3DModels=true "
#curl_addi=" --form useProfile=false "
#culr_addi=" --form email=test@proteinmodelportal.org "


#-> parse arguments
while getopts ":i:t:o:d:n:a:k:l:L:U:" opt;
do
	case $opt in
	#-> required arguments
	i)
		input_fasta=$OPTARG
		;;
	t)
		server_type=$OPTARG
		;;
	o)
		out_root=$OPTARG
		;;
	#-> optional arguments
	d)
		domain_name=$OPTARG
		;;
	n)
		job_name=$OPTARG
		;;
	a)
		curl_addi=$OPTARG
		;;
	k)
		kill_tmp=$OPTARG
		;;
	l)
		pend_time=$OPTARG
		;;
	L)
		run_time=$OPTARG
		;;
	U)
		url=$OPTARG
		;;
	#-> others
	\?)
		echo "Invalid option: -$OPTARG" >&2
		exit 1
		;;
	:)
		echo "Option -$OPTARG requires an argument." >&2
		exit 1
		;;
	esac
done


# ------ check required arguments ------ #
if [ ! -f "$input_fasta" ]
then
	echo "input_fasta $input_fasta not found !!" >&2
	exit 1
fi

if [ "$server_type" == "" ]
then
	echo "server_type must be specified as either 'property' or 'contact' " >&2
	exit 1
fi

if [ "$out_root" == "" ]
then
	echo "out_root should not be blank !!" >&2
	exit 1
fi


#-------- assign url -------------#
property_url="$domain_name/StructurePropertyPred/curl/"
contact_url="$domain_name/ContactMap/curl/"
curl_url=""

# ------ determine curl_url ------- #
if [ "$server_type" == "property" ]
then
	curl_url=$property_url
fi
if [ "$server_type" == "contact" ]
then
	curl_url=$contact_url
fi
if [ "$curl_url" == "null" ]
then
	echo "server_type must be specified as either 'property' or 'contact' " >&2
	exit 1
fi


# ------ related path ------ #
#-> get job id:
fulnam=`basename $input_fasta`
relnam=${fulnam%.*}


if [ "$job_name" == "null" ]
then
	job_name=$relnam
fi

# ----- output folder --- #
mkdir -p $out_root

# ----- tmp folders ----- #
rand="$RANDOM"
tmp=$server_type"_"$rand"_"$relnam
mkdir -p $tmp

# ---- get sequence -------#
cp $input_fasta $tmp/$relnam.fasta
sequence=`tail -n1 $tmp/$relnam.fasta`


# ---- use curl to submit the job ----- #
if [ "$url" == "" ]
then
	curl --form jobname=$job_name --form sequences=$sequence $curl_addi $curl_url 1> $tmp/$relnam.ws1 2> $tmp/$relnam.ws2
else
	cp $url $tmp/$relnam.ws1
fi
job_url=`head -n1 $tmp/$relnam.ws1 | awk '{print $2}'`
job_id=`echo $job_url | awk -F '[_]' '{print $NF}'`
down_url=`tail -n1 $tmp/$relnam.ws1 | awk '{print $2}'`

# ---- check job pending or not ---#
timer=0
broke=0
while true
do
	#-> wget index file
	curl $job_url -o $tmp/$relnam.tmp -s
	reso=`grep "progressBar.set('value',0);" $tmp/$relnam.tmp | wc | awk '{print $1}'`
	if [ $reso -ge 1 ]
	then
		broke=0
	else
		broke=1
	fi
	#-> break or not
	if [ $broke -eq 1 ]
	then
		break
	fi
	#-> sleep
	echo "$server_type job $job_name with id $job_id still not begin : $timer / $pend_time min"
	sleep 1m
	((timer++))
	if [ $timer -gt $pend_time ]
	then
		echo "pending time limit $pend_time min is up, still not begin" >&2
		exit
	fi
done

# ---- check job done or not -----#
timer=0
while true
do
	#-> wget result file
	curl $down_url -o $tmp/$relnam.zip -s
	reso=`head -n1 $tmp/$relnam.zip`
	if [ "$reso" != "File not found." ]
	then
		break
	fi
	#-> sleep
	echo "$server_type job $job_name with id $job_id still not finish: $timer / $run_time min "
	sleep 1m
	#-> timer
	((timer++))
	if [ $timer -gt $run_time ]
	then
		echo "running timelimit $run_time min is up, still not finish" >&2
		exit 1
	fi 
done


# ---- post-process jobs -----#
unzip -q $tmp/$relnam.zip -d $tmp/
echo "$server_type job $job_name with id $job_id is finished and saved to $tmp/$job_id" 

#------ processed file for property ------ #
if [ "$server_type" == "property" ] 
then

#-> copy
cp -r $tmp/$job_id/* $out_root/

#-> rename
for suf in ss8 ss3 acc diso
do
	#--| move detailed result
	mv $out_root/$job_id.$suf.txt $out_root/$job_name.$suf
	OUT=$?
	if [ $OUT -ne 0 ]
	then
		echo "failed in mv $out_root/$job_id.$suf.txt $out_root/$job_name.$suf"
		exit 1
	fi
	#--| proc simplified result
	echo ">$job_name" > $out_root/$job_name.${suf}_simp
	grep -v "^>" $out_root/$job_id.${suf}_simp.txt >> $out_root/$job_name.${suf}_simp
	rm -f $out_root/$job_id.${suf}_simp.txt
done
mv $out_root/$job_id.all.txt $out_root/$job_name.all
mv $out_root/$job_id.seq.txt $out_root/$job_name.seq
mv $out_root/$job_id.fasta.txt $out_root/$job_name.fasta
mv $out_root/Profile_data/$job_id.tgt $out_root/$job_name.tgt
mv $out_root/Profile_data/$job_id.a3m $out_root/$job_name.a3m
rmdir $out_root/Profile_data
rm -rf $out_root/Windows

fi

#------ processed file for property ------ #
if [ "$server_type" == "contact" ]
then

#-> copy
cp -r $tmp/$job_id.all_in_one/* $out_root/

#-> rename file
for suf in png gcnn fasta a2m
do
	mv $out_root/$job_id.$suf $out_root/$job_name.$suf
	OUT=$?
	if [ $OUT -ne 0 ]
	then
		echo "failed in mv $out_root/$job_id.$suf $out_root/$job_name.$suf"
		exit 1
	fi
done
#-> rename contact map
mv $out_root/$job_id.contactmap.txt $out_root/$job_name.contactmap
if [ -f $out_root/$job_id.distcbprob.pkl ]
then
	mv $out_root/$job_id.distcbprob.pkl $out_root/$job_name.distcbprob.pkl
	OUT=$?
	if [ $OUT -ne 0 ]
	then
		echo "failed in mv $out_root/$job_id.distcbprob.pkl $out_root/$job_name.distcbprob.pkl" 
		exit 1
	fi
fi
#-> rename model
for ((i=1;i<=5;i++))
do
	if [ -f $out_root/models/${job_id}_model_$i.pdb ]
	then
		mv $out_root/models/${job_id}_model_$i.pdb $out_root/models/${job_name}_model_$i.pdb
		OUT=$?
		if [ $OUT -ne 0 ]
		then
			echo "failed in mv $out_root/models/${job_id}_model_$i.pdb $out_root/models/${job_name}_model_$i.pdb" 
			exit 1
		fi
	fi
done
if [ -f $out_root/models/$job_id.model_summary ]
then
	mv $out_root/models/$job_id.model_summary $out_root/models/$job_name.model_summary
	OUT=$?
	if [ $OUT -ne 0 ]
	then
		echo "failed in mv $out_root/models/$job_id.model_summary $out_root/models/$job_name.model_summary"
		exit 1
	fi
fi

fi

#------ move job_url and down_url to output root -----#
cp $tmp/$relnam.ws1 $out_root/$job_name.url


#------------------ remove temporary files ----------------#
if [ $kill_tmp -eq 1 ]
then
	rm -rf $tmp
fi


# ========== exit =========== #
exit 0


