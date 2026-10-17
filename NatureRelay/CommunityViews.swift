import SwiftUI

struct CommunityFeedView: View {
    @ObservedObject var store: CommunityStore
    var observations: [NatureObservation] = []
    var onSelectArchive: (NatureObservation) -> Void = { _ in }
    @State private var selection = 0
    @State private var selectedPost: CommunityPost?
    @State private var showsPeople = false
    private var visiblePosts: [CommunityPost] { selection == 1 ? store.followingPosts : store.posts }
    private var archive: [NatureObservation] { observations.filter { $0.isCommunity || $0.isSourceArchive == true } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("NATURE RELAY").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(NRTheme.muted)
                        Text("Field dispatches").font(.system(size: 31, weight: .semibold, design: .serif)).tracking(-0.7)
                        Text("Photos and conversations from people who look closer.")
                            .font(.system(size: 14)).foregroundStyle(NRTheme.muted).lineSpacing(4)
                    }
                    Spacer(minLength: 10)
                    Button { showsPeople = true } label: {
                        Image(systemName: "person.2").font(.system(size: 20, weight: .light))
                            .frame(width: 43, height: 43).background(NRTheme.lime, in: Circle())
                    }.accessibilityLabel("Find people and edit your community nickname")
                }.padding(.horizontal, 24).padding(.top, 24)
                HStack(spacing: 24) {
                    filter("Community", index: 0)
                    filter("Following", index: 1)
                    filter("Archive", index: 2)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 24)

                if selection == 2 {
                    Text("Public iNaturalist records, credited to their original observers. These are archive sightings.")
                        .font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3).padding(.horizontal, 24)
                    LazyVStack(spacing: 0) {
                        ForEach(archive) { item in
                            Button { onSelectArchive(item) } label: { ArchiveDispatchRow(observation: item) }.buttonStyle(.plain)
                        }
                    }
                } else {
                    if let error = store.error {
                        CommunityFailure(message: error) { Task { await store.refresh(followingOnly: selection == 1) } }.padding(.horizontal, 24)
                    }
                    if store.isLoading && store.posts.isEmpty {
                        ProgressView("Loading shared discoveries…").frame(maxWidth: .infinity).padding(.vertical, 60)
                    } else if visiblePosts.isEmpty {
                        VStack(spacing: 13) {
                            Image(systemName: selection == 1 ? "person.2" : "leaf")
                                .font(.system(size: 40, weight: .ultraLight)).foregroundStyle(NRTheme.green).padding(.bottom, 6)
                            Text(selection == 1 ? "Follow a fellow observer." : "The next dispatch could be yours.")
                                .font(.system(size: 22, design: .serif)).multilineTextAlignment(.center)
                            Text(selection == 1 ? "Find people or open a shared discovery to follow its author. Their posts will appear here." : "Open one of your own photos in Journal and choose Publish to community. Your private photos stay in your journal until you publish.")
                                .font(.system(size: 14)).foregroundStyle(NRTheme.muted).multilineTextAlignment(.center).lineSpacing(4)
                            if selection == 1 {
                                Button("Find people") { showsPeople = true }.font(.system(size: 14, weight: .semibold)).padding(.top, 6)
                            }
                        }.frame(maxWidth: .infinity).padding(.horizontal, 34).padding(.vertical, 48)
                    } else {
                        LazyVStack(spacing: 26) {
                            ForEach(visiblePosts) { post in
                                CommunityDispatchRow(post: post, store: store) { selectedPost = post }
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10))
                        Text("Refreshes while open · pull to refresh")
                    }.font(.system(size: 11)).foregroundStyle(NRTheme.muted).frame(maxWidth: .infinity).padding(.top, 6)
                }
            }.padding(.bottom, 30)
        }
        .background(NRTheme.cream).foregroundStyle(NRTheme.ink)
        .refreshable { await store.refresh(followingOnly: selection == 1) }
        .task(id: selection) {
            guard selection != 2 else { return }
            do { try await store.refreshBlockedUsers() } catch { store.error = error.localizedDescription }
            await store.refresh(followingOnly: selection == 1)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(20)) } catch { break }
                guard !Task.isCancelled else { break }
                await store.refresh(followingOnly: selection == 1)
            }
        }
        .sheet(item: $selectedPost) { post in CommunityPostDetailView(post: post, store: store) }
        .sheet(isPresented: $showsPeople) { CommunityPeopleView(store: store) }
        .onChange(of: store.blockedUsers) { _, _ in
            if let selectedPost, store.isBlocked(selectedPost.author.id) { self.selectedPost = nil }
        }
    }

    private func filter(_ title: String, index: Int) -> some View {
        Button { selection = index } label: {
            VStack(spacing: 9) {
                Text(title).font(.system(size: 14, weight: selection == index ? .semibold : .regular))
                    .foregroundStyle(selection == index ? NRTheme.ink : NRTheme.muted)
                Rectangle().fill(selection == index ? NRTheme.green : .clear).frame(height: 2)
            }.fixedSize(horizontal: true, vertical: false)
        }.buttonStyle(.plain).accessibilityAddTraits(selection == index ? .isSelected : [])
    }
}

private struct CommunityDispatchRow: View {
    let post: CommunityPost
    @ObservedObject var store: CommunityStore
    let onSelect: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                CommunityAvatar(name: post.author.nickname)
                VStack(alignment: .leading, spacing: 3) {
                    Text(post.author.nickname).font(.system(size: 13, weight: .semibold))
                    Text(post.locality).font(.system(size: 12)).foregroundStyle(NRTheme.muted)
                }
                Spacer()
                Text(post.createdAt, style: .relative).font(.system(size: 10)).foregroundStyle(NRTheme.muted)
                if post.author.id != store.user?.id {
                    CommunitySafetyMenu(target: .post, targetID: post.id, author: post.author, store: store)
                }
            }.padding(.horizontal, 24)
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 14) {
                    if post.displayImageURL != nil {
                        GeometryReader { geometry in
                            ObservationImage(name: nil, remoteURL: post.displayImageURL)
                                .frame(width: geometry.size.width, height: 255).clipped()
                                .overlay(alignment: .bottomTrailing) { CommunityCompanion(post: post, size: 78).padding(14) }
                                .overlay(alignment: .bottomLeading) {
                                    if post.isReference {
                                        Text("ARCHIVE REFERENCE").font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .padding(.horizontal, 10).padding(.vertical, 7).background(NRTheme.cream, in: Capsule()).padding(15)
                                    }
                                }
                        }.frame(height: 255)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        if post.isPendingModeration { CommunityPendingNotice(content: "dispatch") }
                        Text(post.displayName).font(.system(size: 25, weight: .medium, design: .serif)).tracking(-0.5)
                        if !post.note.isEmpty { Text(post.note).font(.system(size: 13)).foregroundStyle(NRTheme.muted).lineSpacing(3).lineLimit(3) }
                        if post.isReference, let sourceAuthor = post.sourceAuthor {
                            Text("Original observation by \(sourceAuthor)").font(.system(size: 11)).foregroundStyle(NRTheme.muted)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.right")
                            Text(post.commentCount == 1 ? "1 comment" : "\(post.commentCount) comments")
                            Spacer()
                            Text("Observed \(post.observedAt.formatted(date: .abbreviated, time: .omitted))")
                        }.font(.system(size: 11)).foregroundStyle(NRTheme.muted).padding(.top, 6)
                    }.padding(.horizontal, 24)
                }.multilineTextAlignment(.leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open \(post.displayName) by \(post.author.nickname)")
            Rectangle().fill(NRTheme.ink.opacity(0.10)).frame(height: 0.5).padding(.horizontal, 24)
        }
    }
}

private struct ArchiveDispatchRow: View {
    let observation: NatureObservation
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 15) {
                ObservationImage(name: observation.originalImageName, remoteURL: observation.sourcePhotoURL)
                    .frame(width: 92, height: 104).clipped()
                VStack(alignment: .leading, spacing: 6) {
                    Text(observation.commonName ?? observation.name).font(.system(size: 20, design: .serif)).lineLimit(2)
                    Text(observation.author).font(.system(size: 12, weight: .medium))
                    Text(observation.locationLabel).font(.system(size: 11)).lineLimit(2)
                    Text(observation.observationDayLabel).font(.system(size: 11))
                    Text("iNaturalist archive").font(.system(size: 10, weight: .medium)).foregroundStyle(NRTheme.green)
                }.foregroundStyle(NRTheme.muted)
                Spacer(minLength: 0)
            }.padding(.vertical, 17)
            Divider()
        }.padding(.horizontal, 24)
    }
}

struct PublishObservationView: View {
    let observation: NatureObservation
    @ObservedObject var store: CommunityStore
    var onPublished: (CommunityPost) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = "Tomoki"
    @State private var name = ""
    @State private var note = ""
    @State private var locality = ""
    @State private var sharesLocation = true
    @State private var acceptsStandards = false
    @State private var error: String?
    private var isReference: Bool { CommunityReference.isReference(observation) }
    private var isUnsupportedReference: Bool { isReference && !CommunityReference.isSupported(observation) }
    private var coordinateLabel: String {
        String(format: "%.2f, %.2f", (observation.latitude * 100).rounded() / 100, (observation.longitude * 100).rounded() / 100)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ObservationImage(name: observation.originalImageName, remoteURL: observation.sourcePhotoURL)
                        .frame(height: 210).clipped()
                    VStack(alignment: .leading, spacing: 22) {
                        Text(isUnsupportedReference ? "Keep this reference in your journal." : isReference ? "Pass along a field record." : "Send a field dispatch.")
                            .font(.system(size: 28, weight: .medium, design: .serif))
                        if isReference {
                            Text("This is an archive reference, observed \(observation.observationDayLabel) by \(observation.author). The original observer and photo credit stay attached.")
                                .font(.system(size: 13)).foregroundStyle(NRTheme.muted).lineSpacing(4)
                            if isUnsupportedReference {
                                Text(CommunityReference.restrictionMessage).font(.system(size: 13, weight: .medium)).foregroundStyle(NRTheme.green).lineSpacing(4)
                                if let credit = observation.sourceAttribution { Text(credit).font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3) }
                            }
                        } else {
                            Text("A small photo copy, your note and your chosen area will be public after manual review. Your original stays in your journal.")
                                .font(.system(size: 13)).foregroundStyle(NRTheme.muted).lineSpacing(4)
                        }
                        Text("Every new dispatch, including archive references, is reviewed by the developer before other people can see it. You can see your pending submission.")
                            .font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3)
                        field("YOUR PUBLIC NICKNAME") { TextField("Nickname", text: $nickname).textContentType(.nickname).autocorrectionDisabled() }
                        field("DISCOVERY NAME") { TextField("Plant or animal name", text: $name) }
                        field("FIELD NOTE") { TextField("What did you notice?", text: $note, axis: .vertical).lineLimit(3...7) }
                        field("PUBLIC CITY OR AREA") { TextField("For example, Cupertino", text: $locality).textContentType(.addressCity) }
                        VStack(alignment: .leading, spacing: 9) {
                            Toggle("Show an approximate spot on the map", isOn: $sharesLocation).font(.system(size: 14)).tint(NRTheme.green)
                            Text(sharesLocation ? "Public map point: \(coordinateLabel). Coordinates are rounded to 0.01° (roughly 1 km)." : "This post will have no map coordinates. Only the area name above will be public.")
                                .font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3)
                        }
                        if !isReference {
                            Text("The shared photo is limited to 128 KB and has its GPS and camera metadata removed.")
                                .font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Share nature observations and photos you own or have permission to share. Keep original photo credits. Do not post abuse, sexual or violent content, spam, or another person's private information.")
                                .font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3)
                            Link("Read Community Standards", destination: CommunityPolicy.standardsURL)
                                .font(.system(size: 13, weight: .medium))
                            Toggle("I agree to the Community Standards and publishing rules.", isOn: $acceptsStandards)
                                .font(.system(size: 13)).tint(NRTheme.green)
                            Link("Privacy policy", destination: CommunityPolicy.privacyURL).font(.system(size: 12))
                        }
                        if let error { Text(error).font(.system(size: 13)).foregroundStyle(.red).accessibilityIdentifier("communityPublishError") }
                        Button {
                            Task {
                                do {
                                    let post = try await store.publish(observation: observation, name: name, note: note, locality: locality, shareLocation: sharesLocation, nickname: nickname)
                                    onPublished(post)
                                    dismiss()
                                } catch { self.error = error.localizedDescription }
                            }
                        } label: {
                            HStack(spacing: 9) {
                                if store.isPublishing { ProgressView().tint(NRTheme.cream) }
                                Text(isUnsupportedReference ? "Private reference only" : store.isPublishing ? "Submitting…" : "Submit for moderation").font(.system(size: 15, weight: .semibold))
                            }.frame(maxWidth: .infinity).padding(.vertical, 16).background(NRTheme.green).foregroundStyle(NRTheme.cream)
                        }
                        .disabled(isUnsupportedReference || !acceptsStandards || store.isPublishing || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || locality.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(store.isPublishing ? 0.75 : 1).accessibilityIdentifier("communityPublishButton")
                    }.padding(.horizontal, 24).padding(.bottom, 30)
                }
            }.background(NRTheme.cream).foregroundStyle(NRTheme.ink)
                .navigationTitle(isUnsupportedReference ? "Private reference" : isReference ? "Share a reference" : "Publish discovery").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isPublishing) } }
        }.tint(NRTheme.green)
            .interactiveDismissDisabled(store.isPublishing)
            .onAppear {
                nickname = store.user?.nickname ?? "Tomoki"
                name = observation.commonName ?? observation.name
                note = isReference ? "" : observation.note
                locality = observation.locality ?? ""
            }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(NRTheme.muted)
            content().font(.system(size: 15)).padding(.vertical, 8)
            Rectangle().fill(NRTheme.ink.opacity(0.18)).frame(height: 0.5)
        }
    }
}

struct CommunityPostDetailView: View {
    let post: CommunityPost
    @ObservedObject var store: CommunityStore
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [CommunityComment] = []
    @State private var comment = ""
    @State private var nickname = "Tomoki"
    @State private var error: String?
    @State private var isLoading = false
    @State private var isSending = false
    @State private var isFollowing = false
    @State private var followBusy = false
    @State private var showsDelete = false
    @State private var isDeleting = false
    private var current: CommunityPost { store.posts.first(where: { $0.id == post.id }) ?? store.followingPosts.first(where: { $0.id == post.id }) ?? post }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if current.displayImageURL != nil {
                        GeometryReader { geometry in
                            ObservationImage(name: nil, remoteURL: current.displayImageURL)
                                .frame(width: geometry.size.width, height: 270).clipped()
                                .overlay(alignment: .bottomTrailing) { CommunityCompanion(post: current, size: 94).padding(16) }
                        }.frame(height: 270)
                    }
                    VStack(alignment: .leading, spacing: 23) {
                        VStack(alignment: .leading, spacing: 8) {
                            if current.isPendingModeration { CommunityPendingNotice(content: "dispatch") }
                            if current.isReference {
                                Text("ARCHIVE REFERENCE").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(NRTheme.green)
                            }
                            Text(current.displayName).font(.system(size: 32, weight: .medium, design: .serif)).tracking(-0.6)
                            if let scientific = current.scientificName { Text(scientific).font(.system(size: 14).italic()).foregroundStyle(NRTheme.muted) }
                            Text("Observed \(current.observedAt.formatted(date: .abbreviated, time: .omitted)) · \(current.locality)")
                                .font(.system(size: 12)).foregroundStyle(NRTheme.muted)
                        }
                        HStack(spacing: 10) {
                            CommunityAvatar(name: current.author.nickname)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(current.isReference ? "Shared by \(current.author.nickname)" : current.author.nickname).font(.system(size: 14, weight: .semibold))
                            }
                            Spacer()
                            if current.author.id != store.user?.id {
                                Button {
                                    followBusy = true
                                    Task {
                                        do {
                                            var author = current.author
                                            author.isFollowing = isFollowing
                                            isFollowing = try await store.toggleFollow(author)
                                            error = nil
                                        }
                                        catch { self.error = error.localizedDescription }
                                        followBusy = false
                                    }
                                } label: {
                                    Text(isFollowing ? "Following" : "Follow").font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 13).padding(.vertical, 8)
                                        .background(isFollowing ? NRTheme.green.opacity(0.09) : NRTheme.lime, in: Capsule())
                                }.disabled(followBusy).accessibilityLabel(isFollowing ? "Unfollow \(current.author.nickname)" : "Follow \(current.author.nickname)")
                            }
                        }
                        if !current.note.isEmpty { Text(current.note).font(.system(size: 15)).foregroundStyle(NRTheme.muted).lineSpacing(5) }
                        if current.isReference {
                            VStack(alignment: .leading, spacing: 8) {
                                if let author = current.sourceAuthor { Text("Original observation by \(author)").font(.system(size: 13, weight: .semibold)) }
                                if let attribution = current.sourceAttribution { Text(attribution).font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3) }
                                if let source = current.sourceURL, let url = URL(string: source), url.scheme == "https" { Link("View original observation", destination: url).font(.system(size: 13, weight: .medium)) }
                            }
                        }
                        Divider()
                        HStack {
                            Text("Field conversation").font(.system(size: 24, design: .serif))
                            Spacer()
                            if isLoading { ProgressView().controlSize(.small) }
                        }
                        if let error { CommunityFailure(message: error) { Task { await loadComments() } } }
                        if comments.isEmpty && !isLoading {
                            Text("No comments yet. Leave the first field note.").font(.system(size: 14)).foregroundStyle(NRTheme.muted)
                        }
                        ForEach(comments) { item in
                            HStack(alignment: .top, spacing: 10) {
                                CommunityAvatar(name: item.author.nickname, size: 29)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(item.author.nickname).font(.system(size: 12, weight: .semibold))
                                        Spacer()
                                        Text(item.createdAt, style: .relative).font(.system(size: 10)).foregroundStyle(NRTheme.muted)
                                    }
                                    Text(item.text).font(.system(size: 14)).lineSpacing(3).textSelection(.enabled)
                                    if item.isPendingModeration { CommunityPendingNotice(content: "comment") }
                                }
                                if item.author.id != store.user?.id {
                                    CommunitySafetyMenu(target: .comment, targetID: item.id, author: item.author, store: store) {
                                        comments.removeAll { $0.author.id == item.author.id }
                                    }
                                }
                            }.accessibilityElement(children: .contain)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 9) {
                                Text("Posting as").font(.system(size: 12)).foregroundStyle(NRTheme.muted)
                                TextField("Nickname", text: $nickname).font(.system(size: 13, weight: .medium)).textContentType(.nickname).autocorrectionDisabled()
                            }
                            TextField("Add a field note…", text: $comment, axis: .vertical).font(.system(size: 15)).lineLimit(2...5)
                            HStack {
                                Text("Reviewed before public").font(.system(size: 11)).foregroundStyle(NRTheme.muted)
                                Spacer()
                                Button {
                                    isSending = true
                                    Task {
                                        do {
                                            let saved = try await store.comment(postID: current.id, text: comment, nickname: nickname)
                                            if !comments.contains(where: { $0.id == saved.id }) { comments.append(saved) }
                                            comment = ""; error = nil
                                        } catch { self.error = error.localizedDescription }
                                        isSending = false
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        if isSending { ProgressView().controlSize(.small) }
                                        Text(isSending ? "Submitting…" : "Submit comment").font(.system(size: 13, weight: .semibold))
                                    }.padding(.horizontal, 14).padding(.vertical, 10).background(NRTheme.lime, in: Capsule())
                                }.disabled(isSending || comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .accessibilityIdentifier("communityCommentButton")
                            }
                        }
                        Text("Comments refresh every 10 seconds while this conversation is open.")
                            .font(.system(size: 11)).foregroundStyle(NRTheme.muted)
                        Text("New comments are held for manual review. By submitting, you agree to the Community Standards.")
                            .font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3)
                        Link("Community Standards", destination: CommunityPolicy.standardsURL).font(.system(size: 12, weight: .medium))
                    }.padding(.horizontal, 24).padding(.bottom, 35)
                }
            }.background(NRTheme.cream).foregroundStyle(NRTheme.ink)
                .navigationTitle("Field dispatch").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(isDeleting) }
                    ToolbarItem(placement: .topBarLeading) {
                        if current.author.id == store.user?.id {
                            Menu {
                                Button("Delete public dispatch", role: .destructive) { showsDelete = true }
                            } label: {
                                if isDeleting { ProgressView() } else { Image(systemName: "ellipsis.circle") }
                            }.disabled(isDeleting).accessibilityLabel("Dispatch options")
                        } else {
                            CommunitySafetyMenu(target: .post, targetID: current.id, author: current.author, store: store) { dismiss() }
                        }
                    }
                }
                .refreshable { await loadComments(); await store.refresh() }
        }.tint(NRTheme.green)
            .interactiveDismissDisabled(isDeleting)
            .alert("Delete this public dispatch?", isPresented: $showsDelete) {
                Button("Delete dispatch", role: .destructive) {
                    isDeleting = true
                    Task {
                        do { try await store.deletePost(current); dismiss() }
                        catch { self.error = error.localizedDescription; isDeleting = false }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The dispatch and its conversation will disappear from the community. Your original photo stays in your private journal.")
            }
            .onAppear { nickname = store.user?.nickname ?? "Tomoki"; isFollowing = current.isFollowing }
            .onChange(of: current.isFollowing) { _, value in isFollowing = value }
            .onChange(of: store.blockedUsers) { _, _ in
                comments.removeAll { store.isBlocked($0.author.id) }
                if store.isBlocked(current.author.id) { dismiss() }
            }
            .task {
                await loadComments()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(10)) } catch { break }
                    guard !Task.isCancelled else { break }
                    await loadComments()
                }
            }
    }

    private func loadComments() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do { comments = try await store.api.comments(postID: post.id).filter { !store.isBlocked($0.author.id) }; error = nil }
        catch CommunityError.unavailableItem { comments = []; error = nil; dismiss() }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}

struct CommunityPeopleView: View {
    @ObservedObject var store: CommunityStore
    @Environment(\.dismiss) private var dismiss
    @State private var users: [CommunityUser] = []
    @State private var query = ""
    @State private var nickname = "Tomoki"
    @State private var error: String?
    @State private var message: String?
    @State private var isSaving = false
    @State private var busyUser: String?
    @State private var showsDeleteAccount = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    Text("Your name in the field.").font(.system(size: 29, design: .serif))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PUBLIC NICKNAME").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(NRTheme.muted)
                        HStack {
                            TextField("Nickname", text: $nickname).textContentType(.nickname).autocorrectionDisabled()
                            Button(isSaving ? "Saving…" : "Save") {
                                isSaving = true
                                Task {
                                    do { try await store.updateNickname(nickname); message = "Nickname saved."; error = nil; await search() }
                                    catch is CancellationError { }
                                    catch { self.error = error.localizedDescription }
                                    isSaving = false
                                }
                            }.font(.system(size: 13, weight: .semibold)).disabled(isSaving || nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Divider()
                        Text("No email or signup. Your device identity is saved securely on this iPhone. Keep this device to retain access to your posts.")
                            .font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3)
                        Text("New nicknames and changes are reviewed before appearing to other people. Until approval, others see your approved name or ‘Nature observer’.")
                            .font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3)
                        if let message { Text(message).font(.system(size: 12)).foregroundStyle(NRTheme.green) }
                    }
                    Divider()
                    Text("Find fellow observers").font(.system(size: 25, design: .serif))
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(NRTheme.muted)
                        TextField("Search nickname or observer ID", text: $query).font(.system(size: 14)).autocorrectionDisabled().textInputAutocapitalization(.never)
                    }.padding(.vertical, 10)
                    if let error { CommunityFailure(message: error) { Task { await search() } } }
                    if users.isEmpty {
                        Text(store.user == nil ? "Save your nickname above to create a community profile and find fellow observers." : "No observers found. A person appears here after they create a device identity.")
                            .font(.system(size: 14)).foregroundStyle(NRTheme.muted).lineSpacing(4)
                    }
                    ForEach(users) { person in
                        HStack(spacing: 11) {
                            CommunityAvatar(name: person.nickname)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.nickname).font(.system(size: 14, weight: .semibold))
                            }
                            Spacer()
                            if person.id == store.user?.id {
                                Text("You").font(.system(size: 12)).foregroundStyle(NRTheme.muted)
                            } else {
                                Button {
                                    busyUser = person.id
                                    Task {
                                        do { try await store.toggleFollow(person); await search(); error = nil }
                                        catch is CancellationError { }
                                        catch { self.error = error.localizedDescription }
                                        busyUser = nil
                                    }
                                } label: {
                                    Text(person.isFollowing == true ? "Following" : "Follow").font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 13).padding(.vertical, 8).background(NRTheme.lime, in: Capsule())
                                }.disabled(busyUser != nil)
                                CommunitySafetyMenu(target: .user, targetID: person.id, author: person, store: store) {
                                    users.removeAll { $0.id == person.id }
                                }
                            }
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Blocked observers").font(.system(size: 25, design: .serif))
                        Text("Blocking hides each other's dispatches and comments and removes your follow connection. Unblocking does not restore following.")
                            .font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3)
                        if store.blockedUsers.isEmpty {
                            Text("You have no blocked observers.").font(.system(size: 13)).foregroundStyle(NRTheme.muted)
                        }
                        ForEach(store.blockedUsers) { person in
                            HStack(spacing: 11) {
                                CommunityAvatar(name: person.nickname)
                                Text(person.nickname).font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Button(busyUser == person.id ? "Unblocking…" : "Unblock") {
                                    busyUser = person.id
                                    Task {
                                        do { try await store.setBlocked(false, user: person); await search(); error = nil }
                                        catch is CancellationError { }
                                        catch { self.error = error.localizedDescription }
                                        busyUser = nil
                                    }
                                }.font(.system(size: 13, weight: .semibold)).disabled(busyUser != nil)
                            }
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 14) {
                        Link("Community Standards", destination: CommunityPolicy.standardsURL)
                        Link("Privacy policy", destination: CommunityPolicy.privacyURL)
                        Link("Support & contact", destination: CommunityPolicy.supportURL)
                    }.font(.system(size: 14, weight: .medium))
                    if store.user != nil {
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Delete community profile").font(.system(size: 23, design: .serif))
                            Text("Permanently delete your public profile and community data. Your private journal and its original photos stay on this iPhone.")
                                .font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3)
                            Button(store.isDeletingAccount ? "Deleting…" : "Delete community profile", role: .destructive) { showsDeleteAccount = true }
                                .font(.system(size: 14, weight: .semibold)).disabled(isSaving || busyUser != nil || store.isPublishing)
                        }
                    }
                }.padding(24).padding(.bottom, 20)
                    .disabled(store.isDeletingAccount)
            }.background(NRTheme.cream).foregroundStyle(NRTheme.ink)
                .navigationTitle("People & profile").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(store.isDeletingAccount) } }
                .refreshable { await loadBlockedUsers(); await search() }
        }.tint(NRTheme.green)
            .interactiveDismissDisabled(store.isDeletingAccount)
            .alert("Permanently delete your community profile?", isPresented: $showsDeleteAccount) {
                Button("Delete profile and public data", role: .destructive) {
                    Task {
                        do {
                            try await store.deleteAccount()
                            users = []
                            nickname = "Tomoki"
                            message = "Your community profile and public data were deleted. Your private journal is unchanged."
                            error = nil
                            await store.refresh()
                        } catch { self.error = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your profile, public dispatches, uploaded community photos, comments and community connections will be permanently removed. This cannot be undone. Your private journal and original photos are not deleted.")
            }
            .onAppear { nickname = store.user?.nickname ?? "Tomoki" }
            .onChange(of: store.user?.id) { _, id in if id == nil { users = [] } }
            .task { await loadBlockedUsers() }
            .onChange(of: store.blockedUsers) { _, _ in users.removeAll { store.isBlocked($0.id) } }
            .task(id: query) {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                await search()
            }
    }

    private func search() async {
        guard let viewerID = store.user?.id, !store.isDeletingAccount else { users = []; return }
        let requestedQuery = query
        do {
            let fetched = try await store.api.users(query: requestedQuery)
            guard store.user?.id == viewerID, !store.isDeletingAccount, query == requestedQuery else { return }
            users = fetched.filter { !store.isBlocked($0.id) }
            error = nil
        }
        catch is CancellationError { }
        catch {
            guard store.user?.id == viewerID, !store.isDeletingAccount, query == requestedQuery else { return }
            self.error = error.localizedDescription
        }
    }

    private func loadBlockedUsers() async {
        do { try await store.refreshBlockedUsers() }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}

private struct CommunityPendingNotice: View {
    let content: String
    var body: some View {
        Label("Pending moderation — only you can see this \(content)", systemImage: "clock")
            .font(.system(size: 12, weight: .medium)).foregroundStyle(NRTheme.green).lineSpacing(3)
    }
}

private struct CommunitySafetyMenu: View {
    let target: CommunityReportTarget
    let targetID: String
    let author: CommunityUser
    @ObservedObject var store: CommunityStore
    var onBlocked: () -> Void = { }
    @State private var isWorking = false
    @State private var showsBlock = false
    @State private var showsMessage = false
    @State private var message = ""

    var body: some View {
        Menu {
            reportMenu("Report \(target.label)", target: target, id: targetID)
            if target != .user { reportMenu("Report observer", target: .user, id: author.id) }
            Divider()
            Button("Block \(author.nickname)", systemImage: "person.crop.circle.badge.xmark", role: .destructive) { showsBlock = true }
            Link("Community Standards", destination: CommunityPolicy.standardsURL)
            Link("Support & contact", destination: CommunityPolicy.supportURL)
        } label: {
            if isWorking { ProgressView().controlSize(.small) }
            else { Image(systemName: "ellipsis.circle").font(.system(size: 19)).frame(minWidth: 30, minHeight: 32) }
        }.disabled(isWorking || store.isDeletingAccount)
            .accessibilityLabel("Report or block \(author.nickname)")
            .confirmationDialog("Block \(author.nickname)?", isPresented: $showsBlock, titleVisibility: .visible) {
                Button("Block observer", role: .destructive) {
                    isWorking = true
                    Task {
                        do { try await store.setBlocked(true, user: author); onBlocked() }
                        catch is CancellationError { }
                        catch { message = error.localizedDescription; showsMessage = true }
                        isWorking = false
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You will no longer see each other's dispatches or comments. Your follow connection will be removed. Manage blocked observers in People & profile.")
            }
            .alert("Community action", isPresented: $showsMessage) { Button("OK", role: .cancel) { } } message: { Text(message) }
    }

    private func reportMenu(_ title: String, target: CommunityReportTarget, id: String) -> some View {
        Menu(title, systemImage: "flag") {
            ForEach(CommunityReportReason.allCases, id: \.rawValue) { reason in
                Button(reason.label) {
                    isWorking = true
                    Task {
                        do {
                            try await store.report(target: target, id: id, reason: reason)
                            message = "Report received for developer review. You can also block this observer from this menu."
                        } catch is CancellationError { isWorking = false; return }
                        catch { message = error.localizedDescription }
                        isWorking = false
                        showsMessage = true
                    }
                }
            }
        }
    }
}

private struct CommunityCompanion: View {
    let post: CommunityPost
    let size: CGFloat
    private var character: NatureObservation {
        // Coordinates are unused: this value exists only to select illustration artwork.
        var entry = NatureObservation(name: post.name, kind: post.kind, note: "", author: post.author.nickname, latitude: 0, longitude: 0)
        entry.commonName = post.commonName
        entry.scientificName = post.scientificName
        return entry
    }
    var body: some View {
        CompanionArtwork(observation: character, size: size).padding(5)
            .background(NRTheme.cream, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CommunityAvatar: View {
    let name: String
    var size: CGFloat = 32
    var body: some View {
        Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.38, weight: .semibold))
            .frame(width: size, height: size).background(NRTheme.green.opacity(0.10), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct CommunityFailure: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(message).font(.system(size: 13)).lineSpacing(3)
            Button("Try again", action: retry).font(.system(size: 12, weight: .semibold))
        }.foregroundStyle(NRTheme.green).padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
    }
}
