#pragma once

#include "pch.h"

#include <map>
#include <string>
#include <atomic>

#include "directx_peer_conductor.h"
#include "main_window.h"
#include "peer_connection_client.h"

#include "webrtc/base/sigslot.h"

using namespace Microsoft::WRL;
using namespace StreamingToolkit;

using namespace std;
using namespace rtc;
using namespace webrtc;
using namespace sigslot;

class MultiPeerConductor : public PeerConnectionClientObserver,
	public MessageHandler,
	public Runnable,
	public MainWindowCallback,
	public has_slots<>
{
public:
	MultiPeerConductor(shared_ptr<WebRTCConfig> config,
		ID3D11Device* d3d_device,
		bool enable_software_encoder = false);

	~MultiPeerConductor();

	// Connect the signalling implementation to the signalling server
	void ConnectSignallingAsync(const string& client_name);

	// Each peer can emit a signal that will in turn call this method
	void OnIceConnectionChange(int peer_id, PeerConnectionInterface::IceConnectionState new_state);

	void SetMainWindow(MainWindow* main_window);

	void SetDataChannelMessageHandler(const function<void(int, const string&)>& data_channel_handler);

	void SendDataChannelMessage(int peer_id, const string& message);

	virtual void OnSignedIn() override;

	virtual void OnDisconnected() override;

	virtual void OnPeerConnected(int id, const string& name) override;

	virtual void OnPeerDisconnected(int peer_id) override;

	virtual void OnMessageFromPeer(int peer_id, const string& message) override;

	virtual void OnMessageSent(int err) override;

	virtual void OnServerConnectionFailure() override;

	virtual void OnMessage(Message* msg) override;

	virtual void Run(Thread* thread) override;

	const map<int, scoped_refptr<DirectXPeerConductor>>& Peers() const;

	PeerConnectionClient& PeerConnection();

	//-------------------------------------------------------------------------
	// MainWindowCallback implementation.
	//-------------------------------------------------------------------------
	void StartLogin(const std::string& server, int port) override;

	void DisconnectFromServer() override;

	void ConnectToPeer(int peer_id) override;

	void DisconnectFromCurrentPeer() override;

	void UIThreadCallback(int msg_id, void* data) override;

	virtual void Close();

private:
	struct MessageEntry
	{
		int peer;
		string message;
		MessageEntry(int p, const string& s) : peer(p), message(s) {}
	};

	// Handles message received via data channel
	void HandleDataChannelMessage(int peer_id, const string& message);
	
	PeerConnectionClient signalling_client_;
	shared_ptr<WebRTCConfig> webrtc_config_;
	ComPtr<ID3D11Device> d3d_device_;
	bool enable_software_encoder_;
	scoped_refptr<PeerConnectionFactoryInterface> peer_factory_;
	map<int, scoped_refptr<DirectXPeerConductor>> connected_peers_;
	queue<MessageEntry> message_queue_;
	atomic_bool should_process_queue_;
	unique_ptr<Thread> process_thread_;
	function<void(int, const string&)> data_channel_handler_;
	MainWindow* main_window_;
};
