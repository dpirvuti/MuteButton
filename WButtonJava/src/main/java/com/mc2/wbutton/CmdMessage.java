package com.mc2.wbutton;

public class CmdMessage {
	private String nodeId;
	private String cmd; //toggle, state
	private int value;
	
	public CmdMessage() {
	}
	public CmdMessage(String nodeId, String cmd, int value) {
		super();
		this.nodeId = nodeId;
		this.cmd = cmd;
		this.value = value;
	}
	public String getNodeId() {
		return nodeId;
	}
	public void setNodeId(String nodeId) {
		this.nodeId = nodeId;
	}
	public String getCmd() {
		return cmd;
	}
	public void setCmd(String cmd) {
		this.cmd = cmd;
	}
	public int getValue() {
		return value;
	}
	public void setValue(int value) {
		this.value = value;
	}
	@Override
	public String toString() {
		return "CmdMessage [nodeId=" + nodeId + ", cmd=" + cmd + ", value=" + value + "]";
	}
	
	
	
}
