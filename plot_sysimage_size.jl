using Dates, CSV, DataFrames, PlotlyJS

julia_repo() = joinpath(homedir(), "julia")

function process_data(input_file, commit_range="HEAD")
    df = CSV.read(input_file, DataFrame; header=false, delim=' ')
    rename!(df, [:commit, :size])
    commit_range = string(df[!,1][1], "..", df[!,1][end])

    # Get commit dates
    function get_commit_date(commit)
        cmd = `git -C $(julia_repo()) show -s --format=%cd --date=iso-local $commit`
        date_str = chomp(String(read(cmd)))
        DateTime(date_str[1:19], dateformat"yyyy-mm-dd HH:MM:SS")
    end

    df[!, :date] = [get_commit_date(c) for c in df.commit]

    # Track commits to exclude
    excluded_commits = Set{String}()

    # Process merge commits
    merge_commits = readlines(`git -C $(julia_repo()) rev-list --merges $commit_range`)
    for mc in merge_commits
        # Skip and exclude "Merge branch 'master' into" commits
        commit_msg = readchomp(`git -C $(julia_repo()) log --format=%B -1 $mc`)
        if startswith(commit_msg, "Merge branch 'master' into")
            push!(excluded_commits, mc)
            continue
        end

        # Get parent commits
        parents = split(readchomp(`git -C $(julia_repo()) log -1 --format=%P $mc`))
        length(parents) < 2 && continue

        # Get and exclude merged branch commits
        merged_commits = readlines(`git -C $(julia_repo()) rev-list $(parents[2]) --not $(parents[1])`)
        union!(excluded_commits, merged_commits)
    end

    # Filter out excluded commits
    filter!(row -> !(row.commit in excluded_commits), df)
    sort!(df, :date)

    name, ext = splitext(input_file)
    new_name = string(name, "_postprocessed", ext)
    CSV.write(new_name, df; delim = ' ')

    return new_name
end


# Main execution
# df_file = process_data("sysimage_sizes.txt")
df_file = "sysimage_sizes_postprocessed.txt"
processed_data = read(df_file, String)
html_template = read("template.html", String)
html_code = replace(html_template, "___SYSIMAGE_SIZE_DATA___" => processed_data)
write("index.html", html_code)
