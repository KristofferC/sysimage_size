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

    return df
end


# Generate interactive plot
function create_plot(df)
    trace = scatter(
        x=df.date,
        y=df.size,
        mode="markers+lines",
        marker=attr(size=8, color="#2A9D8F"),
        line=attr(color="#264653"),
        text=["Commit: $(row.commit)<br>Date: $(row.date)" for row in eachrow(df)],
        customdata=df.commit,
        hoverinfo="text+y"
    )

    layout = Layout(
        title="Julia Sysimage Size History",
        xaxis_title="Commit Date",
        yaxis_title="Size (bytes)",
        plot_bgcolor="white",
        hovermode="closest",
        showlegend=false,
        annotations=[
            attr(
                x=0.5,
                y=-0.2,
                showarrow=false,
                text="Click points to view commit on GitHub",
                xref="paper",
                yref="paper"
            )
        ]
    )

    return Plot([trace], layout)
end

function save_interactive_plot(plt, filename)
    # Generate base plot HTML
    temp_file = tempname() * ".html"
    savefig(plt, filename)
end

# Main execution
df = process_data("sysimage_sizes.txt")
plt = create_plot(df)
save_interactive_plot(plt, "sysimage_history.html")
