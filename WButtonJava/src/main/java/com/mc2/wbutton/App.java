package com.mc2.wbutton;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.StringWriter;
import java.net.DatagramPacket;
import java.net.InetAddress;
import java.net.MulticastSocket;
import java.net.UnknownHostException;
import java.util.Properties;
import java.util.Timer;
import java.util.TimerTask;
import java.util.logging.Level;
import java.util.logging.Logger;

import com.fasterxml.jackson.core.JsonGenerationException;
import com.fasterxml.jackson.databind.JsonMappingException;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * 
 * @author dpirvuti
 * send sample mcast datagram from command line: socat STDIO UDP4-DATAGRAM:230.0.0.0:7351
 * {"nodeId":"0xef246f28b096", "cmd":"toggle"}
 * {"nodeId":"0xef246f28b096", "cmd":"query"}
 */
public class App {
	protected Logger logger = Logger.getLogger(App.class.getPackage().getName());
	protected Properties appProperties;

	protected String pairedNodeId;
	protected boolean useSystemValue;
	protected int maxInputValue;
	protected Integer initialSystemValue;
	
	protected String setCommand;
	protected String getStateCommand;
	

	public App() {
		appProperties = new Properties();
		try (InputStream appPropertiesStream = this.getClass().getClassLoader().getResourceAsStream("app.properties")) {
			appProperties.load(appPropertiesStream);
		} catch (IOException e) {
			logger.log(Level.SEVERE, "Unable to initialize the app, failed to read app.properties (not on classpath)",
					e);
			System.exit(-1);
		}

		// mcast group address
		String mcastAddressStr = appProperties.getProperty("mcastAddress");
		if (mcastAddressStr == null) {
			logger.severe("Missing required property 'mcastAddress'");
			System.exit(-2);
		}
		InetAddress mcastAddress=null;
		try {
			mcastAddress = InetAddress.getByName(mcastAddressStr);
		} catch (UnknownHostException e1) {
			logger.severe("Invalid format for property 'mcastAddress'");
			System.exit(-3);
		}

		// mcast group port
		String mcastPortStr = appProperties.getProperty("mcastPort");
		if (mcastPortStr == null) {
			logger.severe("Missing required property 'mcastPort'");
			System.exit(-4);
		}
		int mcastPort = 0;
		try {
			mcastPort = Integer.parseInt(mcastPortStr);
		} catch (NumberFormatException e) {
			logger.severe("Invalid format for property 'mcastPort'");
			System.exit(-5);
		}
		// node identifier
		pairedNodeId = appProperties.getProperty("pairedNodeId");
		if (pairedNodeId != null && pairedNodeId.trim().length() == 0) {
			pairedNodeId = null;
		}
		// volume settings
		String maxInputValueStr = appProperties.getProperty("maxInputValue", "100");
		try {
			maxInputValue = Integer.parseInt(maxInputValueStr);
		} catch (NumberFormatException e) {
			logger.severe("Invalid format for property 'maxInputVolume'");
			System.exit(-6);
		}

		String useSystemValueStr = appProperties.getProperty("useSystemValue", "false");
		useSystemValue = Boolean.valueOf(useSystemValueStr).booleanValue();

		//commands
		setCommand = appProperties.getProperty("setCommand");
		getStateCommand = appProperties.getProperty("getStateCommand");
		
		new Thread(new McastReceiver(mcastAddress, mcastPort)).start();
		
	}

	
	
	public class McastReceiver extends Thread {
		private MulticastSocket socket;
		
		private String TOGGLE ="toggle";
		private String STATEQRY="query";
		private String STATE ="state";
		
		private InetAddress mcastAddress;
		private int mcastPort;
		
		public McastReceiver(final InetAddress mcastAddress, int mcastPort) {
			this.mcastAddress = mcastAddress;
			this.mcastPort =mcastPort;
			try {
				socket = new MulticastSocket(mcastPort);
				socket.joinGroup(mcastAddress);
				logger.info("Initialized, waiting for data");
				Timer t= new Timer();
				t.schedule(new TimerTask() {
					@Override
					public void run() {
						try {
							socket.leaveGroup(mcastAddress);
							socket.joinGroup(mcastAddress);
						} catch (IOException e) {
							logger.severe("Unable to rejoin the mcast group");
						}						
					}
				}, 2000, 2000);
			} catch (IOException e) {
				logger.log(Level.SEVERE, "Unable to initialize the mcast component",
						e);
				System.exit(-7);
			}
		}

		@Override
		public void run() {
			ObjectMapper objectMapper = new ObjectMapper();
			while(true) { 
				byte[] buf = new byte[256];
				DatagramPacket packet = new DatagramPacket(buf, buf.length);
			    try {
					socket.receive(packet);
				} catch (IOException e) {
					logger.log(Level.SEVERE, "Failed to receive packet: " + new String(packet.getData()),
							e);
					continue;
				}
			    
			    try { 
			    	CmdMessage cmdMsg = objectMapper.readValue(packet.getData(), CmdMessage.class);
			    	if(pairedNodeId == null && TOGGLE.equals(cmdMsg.getCmd())) {
			    		pairedNodeId = cmdMsg.getNodeId();
			    		logger.info("Auto paired with: " +pairedNodeId);
			    	}
			    	//exec command
			    	logger.info("Received message:"  + cmdMsg);
			    	if(TOGGLE.equals(cmdMsg.getCmd())) {
			    		Integer currentStateValue = getCurrentStateValue();
			    		if(currentStateValue != null) {
			    			//save max value
			    			if(initialSystemValue == null && currentStateValue.intValue() >0) {
			    				initialSystemValue = new Integer(currentStateValue.intValue());
			    			}
			    			int newValue = -1;
			    			if(currentStateValue.intValue() >0 ) {
			    				newValue=0;
			    			}else {
			    				if(initialSystemValue == null) {
			    					newValue = maxInputValue;
			    				}else {
			    					newValue = useSystemValue?initialSystemValue.intValue():maxInputValue;
			    				}
			    			}
			    			if (newValue != -1) { 
			    				if(setValue(newValue) != null) {
			    					//command ok, send reply status
			    					sendReply(cmdMsg.getNodeId(), STATE, newValue, objectMapper);
			    				}
			    			}
			    				
			    		}
			    	}else if(STATEQRY.equals(cmdMsg.getCmd())) {
			    		Integer currentStateValue = getCurrentStateValue();
			    		if(currentStateValue != null) {
		    				//command ok, send reply status
			    			sendReply(cmdMsg.getNodeId(), STATE, currentStateValue.intValue(), objectMapper);
			    		}
			    	}
			    	
			    }catch(Exception ex) {
			    	logger.warning("Failed to process message: "  + new String(packet.getData() )+ ", reason:" + ex.getMessage()) ;
			    }
			}
		}
		
		private void  sendReply(String nodeId, String cmd, int value, ObjectMapper objectMapper) throws JsonGenerationException, JsonMappingException, IOException {
			CmdMessage cmdMsg = new CmdMessage(nodeId, cmd, value);
			StringWriter msgWriter = new StringWriter();
			objectMapper.writeValue(msgWriter, cmdMsg);
			byte[] buf = msgWriter.getBuffer().toString().getBytes();
			DatagramPacket packet = new DatagramPacket(buf, buf.length, mcastAddress, mcastPort);
            socket.send(packet);
            logger.info("Reply sent");
		}
	}
	
	public Integer getCurrentStateValue() throws IOException, InterruptedException {
		String command[ ] = getStateCommand.split("\\|");
		ProcessBuilder pb= new ProcessBuilder(command);
		Process p = pb.start();
		int exitCode = p.waitFor();
		if(exitCode != 0) {
			logger.warning("getStateCommand failed with exit code:" + exitCode);
		}else {
			String out=null;
    		try ( BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()))){
    			out = br.readLine();
    			return Integer.parseInt(out);
    		}catch(NumberFormatException e) {
    			logger.severe("Unable to parse the output of getStateCommand:" + out);
    		}
		}
		return null;
	}
	
	public Integer setValue(int newValue) throws IOException, InterruptedException {
		String command[ ] = setCommand.replace("$value$", String.valueOf(newValue)).split("\\|");
		ProcessBuilder pb= new ProcessBuilder(command);
		Process p = pb.start();
		int exitCode = p.waitFor();
		if(exitCode != 0) {
			logger.warning("setCommand failed with exit code:" + exitCode);
		}else {
			return newValue;
		}
		return null;
	}
	
		

	public static void main(String[] args) {
		new App();
	}
}
 