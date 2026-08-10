## Scenario 1: Find the Last Updated Log Files

I have a folder which has lots of files with the `.log` extension. The name of each of these log files either contains the text "Chapter" or it does not contain it. There is a Perl script which creates these files after processing. 

The requirement is to find the last updated file which has "Chapter" in it and also one which does not have it. The commands used are:

```bash
find . -type f -name "*Chapter*" -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-
find . -type f ! -name "*Chapter*" -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-
```

## Scenario 2: Count Files Based on Time Duration

In the same folder, each of the log files might contain the text "Check with Renderer" followed by a time duration in the format `m:ss`. 

Now the requirement is to find the count of those log files which have a duration of less than 1 minute. The command used to find this is:

```bash
grep -lE "Check with Renderer[[:space:]]+00?:[0-5][0-9]\b" *.log | wc -l
```

## Scenario 3: Calculate Cumulative Time

Now the requirement is we want a cumulative time for values of "Check with Renderer" in all the log files. The command used is:

```bash
grep -h "Check with Renderer" *.log | awk '{ split($NF, t, ":"); total += t[1]*60 + t[2] } END { printf "Total Cumulative Time: %02d:%02d:%02d\n", int(total/3600), int((total%3600)/60), total%60 }'
```
